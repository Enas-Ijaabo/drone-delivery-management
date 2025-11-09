package model

type AssignmentNotice struct {
	OrderID     int64
	DroneID     int64
	PickupLat   float64
	PickupLng   float64
	DropoffLat  float64
	DropoffLng  float64
	EnduserID   int64
	OrderStatus OrderStatus
	Description string
}

func NewAssignmentNotice(order Order, drone Drone) AssignmentNotice {
	return AssignmentNotice{
		OrderID:     order.ID,
		DroneID:     drone.ID,
		PickupLat:   order.PickupLat,
		PickupLng:   order.PickupLng,
		DropoffLat:  order.DropoffLat,
		DropoffLng:  order.DropoffLng,
		EnduserID:   order.EnduserID,
		OrderStatus: order.Status,
		Description: "New delivery assignment",
	}
}
