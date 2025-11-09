package iface

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

const (
	messageTypeHeartbeat     = "heartbeat"
	messageTypeAssignmentAck = "assignment_ack"
)

type DroneHeartbeatUsecase interface {
	Heartbeat(ctx context.Context, droneID int64, hb model.DroneHeartbeat) (*model.Drone, error)
}

type DroneWSHandler struct {
	uc       DroneHeartbeatUsecase
	registry *ConnectionRegistry
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

type assignmentAckRequest struct {
	Type    string `json:"type"`
	OrderID int64  `json:"order_id"`
	Status  string `json:"status"`
	Note    string `json:"note,omitempty"`
}

type assignmentAckResponse struct {
	Type    string `json:"type"`
	OrderID int64  `json:"order_id"`
	Status  string `json:"status"`
	Message string `json:"message"`
}

type assignmentMessage struct {
	Type        string    `json:"type"`
	DroneID     int64     `json:"drone_id"`
	OrderID     int64     `json:"order_id"`
	PickupLat   float64   `json:"pickup_lat"`
	PickupLng   float64   `json:"pickup_lng"`
	DropoffLat  float64   `json:"dropoff_lat"`
	DropoffLng  float64   `json:"dropoff_lng"`
	EnduserID   int64     `json:"enduser_id"`
	OrderStatus string    `json:"order_status"`
	CreatedAt   time.Time `json:"created_at"`
	Description string    `json:"description,omitempty"`
}

func NewDroneWSHandler(uc DroneHeartbeatUsecase, registry *ConnectionRegistry) *DroneWSHandler {
	return &DroneWSHandler{
		uc:       uc,
		registry: registry,
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
	var client *wsClient
	defer func() {
		if client == nil {
			_ = conn.Close()
		}
	}()
	droneID, err := extractDroneID(c)
	if err != nil {
		_ = conn.WriteJSON(heartbeatResponse{
			Type:    "heartbeat",
			Message: "unauthorized",
			Error:   err.Error(),
		})
		return
	}

	client = h.registry.Register(droneID, conn)
	defer h.registry.Unregister(droneID, client)

	ctx := c.Request.Context()

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("heartbeat websocket read error: %v", err)
			}
			return
		}

		var envelope struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(raw, &envelope); err != nil {
			h.writeError(client, fmt.Errorf("invalid message: %w", err))
			continue
		}
		msgType := strings.ToLower(envelope.Type)
		if msgType == "" {
			msgType = messageTypeHeartbeat
		}

		switch msgType {
		case messageTypeHeartbeat:
			var payload heartbeatRequest
			if err := json.Unmarshal(raw, &payload); err != nil {
				h.writeError(client, fmt.Errorf("invalid heartbeat payload: %w", err))
				continue
			}
			h.processHeartbeat(ctx, client, droneID, payload)
		case messageTypeAssignmentAck:
			var ack assignmentAckRequest
			if err := json.Unmarshal(raw, &ack); err != nil {
				h.writeError(client, fmt.Errorf("invalid assignment ack payload: %w", err))
				continue
			}
			h.processAssignmentAck(client, droneID, ack)
		default:
			h.writeError(client, fmt.Errorf("unknown message type: %s", envelope.Type))
		}
	}
}

func (h *DroneWSHandler) NotifyAssignment(ctx context.Context, notice model.AssignmentNotice) error {
	if h == nil || h.registry == nil {
		return nil
	}

	msg := toAssignmentMessage(notice)

	if err := h.registry.Send(notice.DroneID, msg); err != nil {
		return err
	}
	return nil
}

func (h *DroneWSHandler) processHeartbeat(ctx context.Context, client *wsClient, droneID int64, payload heartbeatRequest) {
	hb, err := toHeartbeatModel(payload)
	if err != nil {
		h.writeError(client, err)
		return
	}

	if _, err := h.uc.Heartbeat(ctx, droneID, hb); err != nil {
		h.writeError(client, err)
		return
	}

	h.writeOK(client)
}

func (h *DroneWSHandler) processAssignmentAck(client *wsClient, droneID int64, ack assignmentAckRequest) {
	status := strings.ToLower(ack.Status)
	if ack.OrderID == 0 {
		h.writeError(client, errors.New("order_id is required for assignment ack"))
		return
	}
	if status != "accepted" && status != "declined" {
		h.writeError(client, errors.New("status must be accepted or declined"))
		return
	}

	log.Printf("assignment ack: drone=%d order=%d status=%s note=%s", droneID, ack.OrderID, status, ack.Note)

	resp := toAssignmentAckResponse(ack.OrderID, status, "acknowledged")
	if err := client.Send(resp); err != nil {
		log.Printf("assignment ack response error: %v", err)
	}
}

func (h *DroneWSHandler) writeOK(client *wsClient) {
	resp := toHeartbeatResponse("ok", nil)
	if err := client.Send(resp); err != nil {
		log.Printf("heartbeat websocket write error: %v", err)
	}
}

func (h *DroneWSHandler) writeError(client *wsClient, err error) {
	resp := toHeartbeatResponse("error", err)
	if err := client.Send(resp); err != nil {
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

func toHeartbeatResponse(msg string, err error) heartbeatResponse {
	resp := heartbeatResponse{
		Type:      messageTypeHeartbeat,
		Message:   msg,
		Timestamp: time.Now().UTC(),
	}
	if err != nil {
		resp.Error = err.Error()
	}
	return resp
}

func toAssignmentMessage(notice model.AssignmentNotice) assignmentMessage {
	return assignmentMessage{
		Type:        "assignment",
		DroneID:     notice.DroneID,
		OrderID:     notice.OrderID,
		PickupLat:   notice.PickupLat,
		PickupLng:   notice.PickupLng,
		DropoffLat:  notice.DropoffLat,
		DropoffLng:  notice.DropoffLng,
		EnduserID:   notice.EnduserID,
		OrderStatus: string(notice.OrderStatus),
		CreatedAt:   time.Now().UTC(),
	}
}

func toAssignmentAckResponse(orderID int64, status, message string) assignmentAckResponse {
	return assignmentAckResponse{
		Type:    messageTypeAssignmentAck,
		OrderID: orderID,
		Status:  status,
		Message: message,
	}
}
