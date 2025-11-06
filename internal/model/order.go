package model

import (
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/domain"
)

type Order struct {
	ID              int64
	EnduserID       int64
	AssignedDroneID *int64
	PickupLat       float64
	PickupLng       float64
	DropoffLat      float64
	DropoffLng      float64
	HandoffLat      *float64
	HandoffLng      *float64
	Status          OrderStatus
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

type OrderStatus string

const (
	OrderPending        OrderStatus = "pending"
	OrderReserved       OrderStatus = "reserved"
	OrderPickedUp       OrderStatus = "picked_up"
	OrderHandoffPending OrderStatus = "handoff_pending"
	OrderDelivered      OrderStatus = "delivered"
	OrderFailed         OrderStatus = "failed"
	OrderCanceled       OrderStatus = "canceled"
)

var allowedOrderTransitions = map[OrderStatus][]OrderStatus{
	OrderPending: {
		OrderReserved,
		OrderCanceled,
	},
	OrderReserved: {
		OrderPickedUp,
		OrderFailed,
	},
	OrderPickedUp: {
		OrderHandoffPending,
		OrderDelivered,
		OrderFailed,
	},
	OrderHandoffPending: {
		OrderReserved,
		OrderFailed,
	},
	OrderDelivered: {},
	OrderFailed:    {},
	OrderCanceled:  {},
}

func (o *Order) IsStatusTransitionAllowed(newStatus OrderStatus) bool {
	allowedTransitions, exists := allowedOrderTransitions[o.Status]
	if !exists {
		return false
	}

	for _, allowed := range allowedTransitions {
		if allowed == newStatus {
			return true
		}
	}

	return false
}

func (o *Order) UpdateStatus(newStatus OrderStatus) error {
	if !o.IsStatusTransitionAllowed(newStatus) {
		return domain.ErrOrderTransitionNotAllowed(string(o.Status), string(newStatus))
	}

	o.Status = newStatus
	return nil
}
