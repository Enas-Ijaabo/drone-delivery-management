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

const (
	paramOrderID            = "id"
	queryParamStatus        = "status"
	queryParamEnduserID     = "enduser_id"
	queryParamAssignedDrone = "assigned_drone_id"
)

type OrderUsecase interface {
	CreateOrder(ctx context.Context, req model.CreateOrderRequest) (*model.Order, error)
	CancelOrder(ctx context.Context, userID, orderID int64) (*model.Order, error)
	GetOrder(ctx context.Context, userID, orderID int64) (*model.OrderDetails, error)
	ReserveOrder(ctx context.Context, droneID, orderID int64) (*model.Order, error)
	PickupOrder(ctx context.Context, droneID, orderID int64) (*model.Order, error)
	DeliverOrder(ctx context.Context, droneID, orderID int64) (*model.Order, error)
	FailOrder(ctx context.Context, droneID, orderID int64) (*model.Order, error)
	UpdateRoute(ctx context.Context, orderID int64, req model.UpdateRouteRequest) (*model.Order, error)
	ListOrders(ctx context.Context, filters model.OrderListFilters, page, pageSize int) ([]model.Order, model.Pagination, error)
}

type OrderHandler struct {
	uc OrderUsecase
}

func NewOrderHandler(uc OrderUsecase) *OrderHandler {
	return &OrderHandler{uc: uc}
}

type createOrderRequest struct {
	PickupLat  *float64 `json:"pickup_lat" binding:"required"`
	PickupLng  *float64 `json:"pickup_lng" binding:"required"`
	DropoffLat *float64 `json:"dropoff_lat" binding:"required"`
	DropoffLng *float64 `json:"dropoff_lng" binding:"required"`
}

type locationResponse struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type orderResponse struct {
	OrderID         int64             `json:"order_id"`
	Status          string            `json:"status"`
	Pickup          locationResponse  `json:"pickup"`
	Dropoff         locationResponse  `json:"dropoff"`
	CreatedAt       time.Time         `json:"created_at"`
	UpdatedAt       time.Time         `json:"updated_at,omitempty"`
	CanceledAt      *time.Time        `json:"canceled_at,omitempty"`
	AssignedDroneID *int64            `json:"assigned_drone_id,omitempty"`
	DroneLocation   *locationResponse `json:"drone_location,omitempty"`
	ETAMinutes      *model.ETA        `json:"eta_minutes,omitempty"`
	HandoffLat      *float64          `json:"handoff_lat,omitempty"`
	HandoffLng      *float64          `json:"handoff_lng,omitempty"`
}

type updateRouteRequest struct {
	PickupLat  *float64 `json:"pickup_lat,omitempty"`
	PickupLng  *float64 `json:"pickup_lng,omitempty"`
	DropoffLat *float64 `json:"dropoff_lat,omitempty"`
	DropoffLng *float64 `json:"dropoff_lng,omitempty"`
}

type orderListResponse struct {
	Data []orderResponse `json:"data"`
	Meta paginationMeta  `json:"meta"`
}

func (h *OrderHandler) CreateOrder(c *gin.Context) {
	var req createOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid or missing coordinates"})
		return
	}

	if *req.PickupLat < -90 || *req.PickupLat > 90 ||
		*req.DropoffLat < -90 || *req.DropoffLat > 90 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "latitude must be between -90 and 90"})
		return
	}
	if *req.PickupLng < -180 || *req.PickupLng > 180 ||
		*req.DropoffLng < -180 || *req.DropoffLng > 180 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "longitude must be between -180 and 180"})
		return
	}

	userIDStr, exists := c.Get(CtxUserID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "missing user id"})
		return
	}

	userID, err := strconv.ParseInt(userIDStr.(string), 10, 64)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid user id"})
		return
	}

	createOrderReq := toCreateOrderModel(req, userID)

	order, err := h.uc.CreateOrder(c.Request.Context(), createOrderReq)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusCreated, toOrderResponse(*order))
}

func (h *OrderHandler) CancelOrder(c *gin.Context) {
	idStr := c.Param(paramOrderID)
	orderID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || orderID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid order id"})
		return
	}

	userIDStr, exists := c.Get(CtxUserID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "missing user id"})
		return
	}
	userID, err := strconv.ParseInt(userIDStr.(string), 10, 64)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid user id"})
		return
	}

	order, err := h.uc.CancelOrder(c.Request.Context(), userID, orderID)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toOrderResponse(*order))
}

func (h *OrderHandler) GetOrder(c *gin.Context) {
	idStr := c.Param(paramOrderID)
	orderID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || orderID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid order id"})
		return
	}

	userIDStr, exists := c.Get(CtxUserID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "missing user id"})
		return
	}
	userID, err := strconv.ParseInt(userIDStr.(string), 10, 64)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid user id"})
		return
	}

	orderDetails, err := h.uc.GetOrder(c.Request.Context(), userID, orderID)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toOrderDetailsResponse(*orderDetails))
}

func (h *OrderHandler) ReserveOrder(c *gin.Context) {
	idStr := c.Param(paramOrderID)
	orderID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || orderID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid order id"})
		return
	}

	droneIDStr, exists := c.Get(CtxUserID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "missing drone id"})
		return
	}
	droneID, err := strconv.ParseInt(droneIDStr.(string), 10, 64)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid drone id"})
		return
	}

	order, err := h.uc.ReserveOrder(c.Request.Context(), droneID, orderID)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toOrderResponse(*order))
}

func (h *OrderHandler) PickupOrder(c *gin.Context) {
	idStr := c.Param(paramOrderID)
	orderID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || orderID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid order id"})
		return
	}

	droneIDStr, exists := c.Get(CtxUserID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "missing drone id"})
		return
	}
	droneID, err := strconv.ParseInt(droneIDStr.(string), 10, 64)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid drone id"})
		return
	}

	order, err := h.uc.PickupOrder(c.Request.Context(), droneID, orderID)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toOrderResponse(*order))
}

func (h *OrderHandler) DeliverOrder(c *gin.Context) {
	idStr := c.Param(paramOrderID)
	orderID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || orderID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid order id"})
		return
	}

	droneIDStr, exists := c.Get(CtxUserID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "missing drone id"})
		return
	}
	droneID, err := strconv.ParseInt(droneIDStr.(string), 10, 64)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid drone id"})
		return
	}

	order, err := h.uc.DeliverOrder(c.Request.Context(), droneID, orderID)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toOrderResponse(*order))
}

func (h *OrderHandler) FailOrder(c *gin.Context) {
	idStr := c.Param(paramOrderID)
	orderID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || orderID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid order id"})
		return
	}

	droneIDStr, exists := c.Get(CtxUserID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "missing drone id"})
		return
	}
	droneID, err := strconv.ParseInt(droneIDStr.(string), 10, 64)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid drone id"})
		return
	}

	order, err := h.uc.FailOrder(c.Request.Context(), droneID, orderID)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toOrderResponse(*order))
}

func (h *OrderHandler) AdminUpdateRoute(c *gin.Context) {
	orderID, err := parseOrderID(c)
	if err != nil {
		return
	}

	var req updateRouteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid json body"})
		return
	}

	if err := validateRouteUpdate(req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	modelReq := model.UpdateRouteRequest{
		PickupLat:  req.PickupLat,
		PickupLng:  req.PickupLng,
		DropoffLat: req.DropoffLat,
		DropoffLng: req.DropoffLng,
	}

	order, err := h.uc.UpdateRoute(c.Request.Context(), orderID, modelReq)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, toOrderResponse(*order))
}

func validateRouteUpdate(req updateRouteRequest) error {
	hasPickup := req.PickupLat != nil || req.PickupLng != nil
	hasDropoff := req.DropoffLat != nil || req.DropoffLng != nil

	if !hasPickup && !hasDropoff {
		return errors.New("pickup or dropoff coordinates are required")
	}

	if hasPickup {
		if req.PickupLat == nil || req.PickupLng == nil {
			return errors.New("pickup_lat and pickup_lng must both be provided")
		}
		if *req.PickupLat < -90 || *req.PickupLat > 90 {
			return errors.New("pickup latitude must be between -90 and 90")
		}
		if *req.PickupLng < -180 || *req.PickupLng > 180 {
			return errors.New("pickup longitude must be between -180 and 180")
		}
	}

	if hasDropoff {
		if req.DropoffLat == nil || req.DropoffLng == nil {
			return errors.New("dropoff_lat and dropoff_lng must both be provided")
		}
		if *req.DropoffLat < -90 || *req.DropoffLat > 90 {
			return errors.New("dropoff latitude must be between -90 and 90")
		}
		if *req.DropoffLng < -180 || *req.DropoffLng > 180 {
			return errors.New("dropoff longitude must be between -180 and 180")
		}
	}

	return nil
}

func parseOrderID(c *gin.Context) (int64, error) {
	idStr := c.Param(paramOrderID)
	orderID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || orderID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid order id"})
		return 0, err
	}
	return orderID, nil
}

func (h *OrderHandler) AdminListOrders(c *gin.Context) {
	filters, err := parseOrderFilters(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	page, pageSize, err := parsePaginationParams(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	orders, pagination, err := h.uc.ListOrders(c.Request.Context(), filters, page, pageSize)
	if err != nil {
		c.Error(err)
		return
	}

	response := toOrderListResponse(orders, pagination)
	c.JSON(http.StatusOK, response)
}

func parseOrderFilters(c *gin.Context) (model.OrderListFilters, error) {
	var filters model.OrderListFilters

	if status := c.Query(queryParamStatus); status != "" {
		s := model.OrderStatus(status)
		if !model.IsValidOrderStatus(s) {
			return filters, errors.New("invalid status")
		}
		filters.Status = &s
	}

	if enduserStr := c.Query(queryParamEnduserID); enduserStr != "" {
		id, err := strconv.ParseInt(enduserStr, 10, 64)
		if err != nil || id <= 0 {
			return filters, errors.New("enduser_id must be a positive integer")
		}
		filters.EnduserID = &id
	}

	if droneStr := c.Query(queryParamAssignedDrone); droneStr != "" {
		id, err := strconv.ParseInt(droneStr, 10, 64)
		if err != nil || id <= 0 {
			return filters, errors.New("assigned_drone_id must be a positive integer")
		}
		filters.AssignedDroneID = &id
	}

	return filters, nil
}

func toOrderListResponse(orders []model.Order, pagination model.Pagination) orderListResponse {
	data := make([]orderResponse, len(orders))
	for i := range orders {
		data[i] = toOrderResponse(orders[i])
	}

	return orderListResponse{
		Data: data,
		Meta: paginationMeta{
			Page:     pagination.Page,
			PageSize: pagination.PageSize,
			HasNext:  pagination.HasNext(len(orders)),
		},
	}
}

func toCreateOrderModel(req createOrderRequest, userID int64) model.CreateOrderRequest {
	return model.CreateOrderRequest{
		EnduserID:  userID,
		PickupLat:  *req.PickupLat,
		PickupLng:  *req.PickupLng,
		DropoffLat: *req.DropoffLat,
		DropoffLng: *req.DropoffLng,
	}
}

func toOrderResponse(order model.Order) orderResponse {
	return orderResponse{
		OrderID: order.ID,
		Status:  string(order.Status),
		Pickup: locationResponse{
			Lat: order.PickupLat,
			Lng: order.PickupLng,
		},
		Dropoff: locationResponse{
			Lat: order.DropoffLat,
			Lng: order.DropoffLng,
		},
		CreatedAt:       order.CreatedAt,
		UpdatedAt:       order.UpdatedAt,
		CanceledAt:      order.CanceledAt,
		AssignedDroneID: order.AssignedDroneID,
		HandoffLat:      order.HandoffLat,
		HandoffLng:      order.HandoffLng,
	}
}

func toOrderDetailsResponse(details model.OrderDetails) orderResponse {
	response := orderResponse{
		OrderID: details.Order.ID,
		Status:  string(details.Order.Status),
		Pickup: locationResponse{
			Lat: details.Order.PickupLat,
			Lng: details.Order.PickupLng,
		},
		Dropoff: locationResponse{
			Lat: details.Order.DropoffLat,
			Lng: details.Order.DropoffLng,
		},
		CreatedAt:       details.Order.CreatedAt,
		UpdatedAt:       details.Order.UpdatedAt,
		CanceledAt:      details.Order.CanceledAt,
		AssignedDroneID: details.Order.AssignedDroneID,
		HandoffLat:      details.Order.HandoffLat,
		HandoffLng:      details.Order.HandoffLng,
	}

	if details.DroneLocation != nil {
		response.DroneLocation = &locationResponse{
			Lat: details.DroneLocation.Lat,
			Lng: details.DroneLocation.Lng,
		}
	}

	if details.ETA != nil {
		response.ETAMinutes = details.ETA
	}

	return response
}
