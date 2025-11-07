package model

import (
	"time"
)

type CreateOrderRequest struct {
	EnduserID  int64
	PickupLat  float64
	PickupLng  float64
	DropoffLat float64
	DropoffLng float64
}

type DroneLocation struct {
	Lat float64
	Lng float64
}

type OrderDetails struct {
	Order         Order
	DroneLocation *DroneLocation
	ETA           *ETA
}

func NewOrderDetails(order Order, drone *Drone) OrderDetails {
	details := OrderDetails{
		Order: order,
	}

	if drone != nil {
		details.DroneLocation = &DroneLocation{
			Lat: drone.Lat,
			Lng: drone.Lng,
		}

		eta := CalculateETA(drone, &order)
		if eta > 0 {
			details.ETA = &eta
		}
	}

	return details
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
	CanceledAt      *time.Time
}

func (o *Order) BelongsTo(userID int64) error {
	if o.EnduserID != userID {
		return ErrOrderNotOwned()
	}
	return nil
}

func (o *Order) IsAssignedTo(droneID int64) error {
	if o.AssignedDroneID == nil || *o.AssignedDroneID != droneID {
		return ErrOrderNotAssignedToDrone()
	}
	return nil
}

func NewOrder(req CreateOrderRequest) *Order {
	return &Order{
		EnduserID:  req.EnduserID,
		PickupLat:  req.PickupLat,
		PickupLng:  req.PickupLng,
		DropoffLat: req.DropoffLat,
		DropoffLng: req.DropoffLng,
		Status:     OrderPending,
	}
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
		return ErrOrderTransitionNotAllowed(string(o.Status), string(newStatus))
	}

	o.Status = newStatus
	return nil
}

func (o *Order) Reserve(droneID int64) error {
	if err := o.UpdateStatus(OrderReserved); err != nil {
		return err
	}
	o.AssignedDroneID = &droneID
	return nil
}

func (o *Order) Deliver() error {
	return o.UpdateStatus(OrderDelivered)
}

func (o *Order) Pickup() error {
	return o.UpdateStatus(OrderPickedUp)
}

func (o *Order) Fail() error {
	return o.UpdateStatus(OrderFailed)
}
