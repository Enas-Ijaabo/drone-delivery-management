package iface

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/gin-gonic/gin"
)

type DroneOpsUsecase interface {
	ReportBroken(ctx context.Context, actorID, droneID int64, actorRole model.Role, location model.DroneHeartbeat) (*model.Drone, *model.Order, error)
	ReportFixed(ctx context.Context, actorID, droneID int64, actorRole model.Role, location model.DroneHeartbeat) (*model.Drone, error)
	ListDrones(ctx context.Context, page, pageSize int) ([]model.Drone, model.Pagination, error)
}

type DroneHandler struct {
	ops DroneOpsUsecase
}

func NewDroneHandler(ops DroneOpsUsecase) *DroneHandler {
	return &DroneHandler{ops: ops}
}

type droneLocationRequest struct {
	Lat *float64 `json:"lat,omitempty"`
	Lng *float64 `json:"lng,omitempty"`
}

type droneStatusResponse struct {
	DroneID           int64      `json:"drone_id"`
	Status            string     `json:"status"`
	Lat               float64    `json:"lat"`
	Lng               float64    `json:"lng"`
	CurrentOrderID    *int64     `json:"current_order_id,omitempty"`
	HandoffOrderID    *int64     `json:"handoff_order_id,omitempty"`
	OrderStatus       *string    `json:"order_status,omitempty"`
	AssignmentPending bool       `json:"assignment_pending"`
	LastHeartbeat     *time.Time `json:"last_heartbeat,omitempty"`
}

type paginationMeta struct {
	Page     int  `json:"page"`
	PageSize int  `json:"page_size"`
	HasNext  bool `json:"has_next"`
}

type droneListResponse struct {
	Data []droneStatusResponse `json:"data"`
	Meta paginationMeta        `json:"meta"`
}

// MarkBroken godoc
// @Summary Report drone as broken
// @Description Report that a drone is broken (can be called by drone or admin)
// @Tags drones
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path int true "Drone ID"
// @Param location body droneLocationRequest true "Drone location"
// @Success 200 {object} droneStatusResponse "Drone marked as broken"
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 404 {object} map[string]string "Drone not found"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /drones/{id}/broken [post]
func (h *DroneHandler) MarkBroken(c *gin.Context) {
	droneIDParam := c.Param("id")
	droneID, err := strconv.ParseInt(droneIDParam, 10, 64)
	if err != nil || droneID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_drone_id", "message": "invalid drone id"})
		return
	}

	subjectID, err := extractSubjectID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": err.Error()})
		return
	}

	subjectRole, err := extractSubjectRole(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": err.Error()})
		return
	}

	var req droneLocationRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.Lat == nil || req.Lng == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "lat and lng are required"})
		return
	}

	location := model.DroneHeartbeat{
		Lat: *req.Lat,
		Lng: *req.Lng,
	}

	drone, order, err := h.ops.ReportBroken(c.Request.Context(), subjectID, droneID, model.Role(subjectRole), location)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toDroneStatusResponse(drone, order))
}

// MarkFixed godoc
// @Summary Mark drone as fixed (Admin action)
// @Description Admin marks a broken drone as fixed and ready for operation
// @Tags admin
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path int true "Drone ID"
// @Param location body droneLocationRequest true "Drone location"
// @Success 200 {object} droneStatusResponse "Drone marked as fixed"
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 403 {object} map[string]string "Forbidden - Admin only"
// @Failure 404 {object} map[string]string "Drone not found"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /admin/drones/{id}/fixed [post]
func (h *DroneHandler) MarkFixed(c *gin.Context) {
	droneIDParam := c.Param("id")
	droneID, err := strconv.ParseInt(droneIDParam, 10, 64)
	if err != nil || droneID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_drone_id", "message": "invalid drone id"})
		return
	}

	subjectID, err := extractSubjectID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": err.Error()})
		return
	}

	subjectRole, err := extractSubjectRole(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": err.Error()})
		return
	}

	var req droneLocationRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.Lat == nil || req.Lng == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "lat and lng are required"})
		return
	}

	location := model.DroneHeartbeat{Lat: *req.Lat, Lng: *req.Lng}

	drone, err := h.ops.ReportFixed(c.Request.Context(), subjectID, droneID, model.Role(subjectRole), location)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toDroneStatusResponse(drone, nil))
}

// List godoc
// @Summary List all drones (Admin action)
// @Description Get a paginated list of all drones with their status
// @Tags admin
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param page query int false "Page number (default: 1)"
// @Param page_size query int false "Page size (default: 10)"
// @Success 200 {object} droneListResponse "List of drones"
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 403 {object} map[string]string "Forbidden - Admin only"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /admin/drones [get]
func (h *DroneHandler) List(c *gin.Context) {
	page, pageSize, err := parsePaginationParams(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	drones, pagination, err := h.ops.ListDrones(c.Request.Context(), page, pageSize)
	if err != nil {
		c.Error(err)
		return
	}

	resp := toDroneListResponse(drones, pagination)
	c.JSON(http.StatusOK, resp)
}

// Response converters

func toDroneStatusResponse(drone *model.Drone, order *model.Order) droneStatusResponse {
	resp := droneStatusResponse{
		DroneID:        drone.ID,
		Status:         string(drone.Status),
		Lat:            drone.Lat,
		Lng:            drone.Lng,
		CurrentOrderID: drone.CurrentOrderID,
		LastHeartbeat:  drone.LastHeartbeat,
	}

	if order != nil {
		resp.HandoffOrderID = &order.ID
		status := string(order.Status)
		resp.OrderStatus = &status
		if order.Status == model.OrderPending || order.Status == model.OrderHandoffPending {
			resp.AssignmentPending = true
		}
	}

	return resp
}

func toDroneListResponse(drones []model.Drone, pagination model.Pagination) droneListResponse {
	data := make([]droneStatusResponse, len(drones))
	for i := range drones {
		data[i] = toDroneStatusResponse(&drones[i], nil)
	}

	return droneListResponse{
		Data: data,
		Meta: toPaginationMeta(pagination, len(drones)),
	}
}

func toPaginationMeta(pagination model.Pagination, resultCount int) paginationMeta {
	return paginationMeta{
		Page:     pagination.Page,
		PageSize: pagination.PageSize,
		HasNext:  pagination.HasNext(resultCount),
	}
}

func extractSubjectID(c *gin.Context) (int64, error) {
	val, exists := c.Get(CtxUserID)
	if !exists {
		return 0, errors.New("missing user id")
	}
	str, ok := val.(string)
	if !ok {
		return 0, errors.New("invalid user id")
	}
	return strconv.ParseInt(str, 10, 64)
}

func extractSubjectRole(c *gin.Context) (string, error) {
	val, exists := c.Get(CtxJWTUserRole)
	if !exists {
		return "", errors.New("missing user role")
	}
	role, ok := val.(string)
	if !ok {
		return "", errors.New("invalid user role")
	}
	return role, nil
}
