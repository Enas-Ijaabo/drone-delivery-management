package model

type AssignmentDescription string

const (
	AssignmentNewOrder AssignmentDescription = "new_order"
	AssignmentHandoff  AssignmentDescription = "handoff"
)

type AssignmentNotice struct {
	OrderID     int64
	DroneID     int64
	PickupLat   float64
	PickupLng   float64
	DropoffLat  float64
	DropoffLng  float64
	EnduserID   int64
	OrderStatus OrderStatus
	Description AssignmentDescription
}

func NewAssignmentNotice(order Order, drone Drone) AssignmentNotice {
	description := AssignmentNewOrder
	if order.Status == OrderHandoffPending {
		description = AssignmentHandoff
	}

	return AssignmentNotice{
		OrderID:     order.ID,
		DroneID:     drone.ID,
		PickupLat:   order.PickupLat,
		PickupLng:   order.PickupLng,
		DropoffLat:  order.DropoffLat,
		DropoffLng:  order.DropoffLng,
		EnduserID:   order.EnduserID,
		OrderStatus: order.Status,
		Description: description,
	}
}
