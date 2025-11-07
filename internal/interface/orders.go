package iface

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/gin-gonic/gin"
)

type OrderUsecase interface {
	CreateOrder(ctx context.Context, req model.CreateOrderRequest) (*model.Order, error)
	CancelOrder(ctx context.Context, userID, orderID int64) (*model.Order, error)
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

type createOrderResponse struct {
	OrderID    int64            `json:"order_id"`
	Status     string           `json:"status"`
	Pickup     locationResponse `json:"pickup"`
	Dropoff    locationResponse `json:"dropoff"`
	CreatedAt  time.Time        `json:"created_at"`
	UpdatedAt  time.Time        `json:"updated_at,omitempty"`
	CanceledAt *time.Time       `json:"canceled_at,omitempty"`
}

func (h *OrderHandler) CreateOrder(c *gin.Context) {
	var req createOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "invalid or missing coordinates"})
		return
	}

	// Validate coordinate ranges
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

	c.JSON(http.StatusCreated, toCreateOrderResponse(*order))
}

func (h *OrderHandler) CancelOrder(c *gin.Context) {
	idStr := c.Param("id")
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

	c.JSON(http.StatusOK, toCreateOrderResponse(*order))
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

func toCreateOrderResponse(order model.Order) createOrderResponse {
	return createOrderResponse{
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
		CreatedAt:  order.CreatedAt,
		UpdatedAt:  order.UpdatedAt,
		CanceledAt: order.CanceledAt,
	}
}
