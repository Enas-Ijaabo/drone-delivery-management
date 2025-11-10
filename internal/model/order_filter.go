package model

type OrderListFilters struct {
	Status          *OrderStatus
	EnduserID       *int64
	AssignedDroneID *int64
}

func (f OrderListFilters) HasAssignedFilters() bool {
	return f.Status != nil || f.EnduserID != nil || f.AssignedDroneID != nil
}

func IsValidOrderStatus(status OrderStatus) bool {
	_, exists := allowedOrderTransitions[status]
	return exists
}
