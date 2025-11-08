package iface

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

type DroneHeartbeatUsecase interface {
	Heartbeat(ctx context.Context, droneID int64, hb model.DroneHeartbeat) (*model.Drone, error)
}

type DroneWSHandler struct {
	uc       DroneHeartbeatUsecase
	upgrader websocket.Upgrader
}

type heartbeatRequest struct {
	Lat *float64 `json:"lat"`
	Lng *float64 `json:"lng"`
}

type heartbeatResponse struct {
	Type      string    `json:"type"`
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	Error     string    `json:"error,omitempty"`
}

func NewDroneWSHandler(uc DroneHeartbeatUsecase) *DroneWSHandler {
	return &DroneWSHandler{
		uc: uc,
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}
}

func (h *DroneWSHandler) HandleHeartbeat(c *gin.Context) {
	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("websocket upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	droneID, err := extractDroneID(c)
	if err != nil {
		_ = conn.WriteJSON(heartbeatResponse{
			Type:    "heartbeat",
			Message: "unauthorized",
			Error:   err.Error(),
		})
		return
	}

	ctx := c.Request.Context()

	for {
		var payload heartbeatRequest
		if err := conn.ReadJSON(&payload); err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("heartbeat websocket read error: %v", err)
			}
			return
		}

		hb, err := toHeartbeatModel(payload)
		if err != nil {
			h.writeError(conn, err)
			continue
		}

		if _, err := h.uc.Heartbeat(ctx, droneID, hb); err != nil {
			h.writeError(conn, err)
			continue
		}

		h.writeOK(conn)
	}
}

func toHeartbeatModel(req heartbeatRequest) (model.DroneHeartbeat, error) {
	if req.Lat == nil {
		return model.DroneHeartbeat{}, errors.New("lat is required")
	}
	if req.Lng == nil {
		return model.DroneHeartbeat{}, errors.New("lng is required")
	}

	return model.DroneHeartbeat{
		Lat: *req.Lat,
		Lng: *req.Lng,
	}, nil
}

func (h *DroneWSHandler) writeOK(conn *websocket.Conn) {
	resp := heartbeatResponse{
		Type:      "heartbeat",
		Message:   "ok",
		Timestamp: time.Now().UTC(),
	}
	if err := conn.WriteJSON(resp); err != nil {
		log.Printf("heartbeat websocket write error: %v", err)
	}
}

func (h *DroneWSHandler) writeError(conn *websocket.Conn, err error) {
	resp := heartbeatResponse{
		Type:      "heartbeat",
		Message:   "error",
		Timestamp: time.Now().UTC(),
		Error:     err.Error(),
	}
	if err := conn.WriteJSON(resp); err != nil {
		log.Printf("heartbeat websocket write error: %v", err)
	}
}

func extractDroneID(c *gin.Context) (int64, error) {
	droneIDVal, exists := c.Get(CtxUserID)
	if !exists {
		return 0, errors.New("missing drone id in context")
	}
	droneIDStr, ok := droneIDVal.(string)
	if !ok {
		return 0, errors.New("invalid drone id format")
	}
	return strconv.ParseInt(droneIDStr, 10, 64)
}
