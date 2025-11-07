package model

import (
	"time"
)

type Drone struct {
	ID             int64
	Status         DroneStatus
	CurrentOrderID *int64
	Lat, Lng       float64
	LastHeartbeat  *time.Time
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

type DroneStatus string

const (
	DroneIdle       DroneStatus = "idle"
	DroneReserved   DroneStatus = "reserved"
	DroneDelivering DroneStatus = "delivering"
	DroneBroken     DroneStatus = "broken"
)

var allowedDroneTransitions = map[DroneStatus][]DroneStatus{
	DroneIdle: {
		DroneReserved,
	},
	DroneReserved: {
		DroneDelivering,
		DroneIdle,
	},
	DroneDelivering: {
		DroneIdle,
		DroneBroken,
	},
	DroneBroken: {
		DroneIdle,
	},
}

func (d *Drone) IsStatusTransitionAllowed(newStatus DroneStatus) bool {
	allowedTransitions, exists := allowedDroneTransitions[d.Status]
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

func (d *Drone) UpdateStatus(newStatus DroneStatus) error {
	if !d.IsStatusTransitionAllowed(newStatus) {
		return ErrDroneTransitionNotAllowed(string(d.Status), string(newStatus))
	}

	d.Status = newStatus
	return nil
}

func (d *Drone) Reserve(orderID int64) error {
	if err := d.UpdateStatus(DroneReserved); err != nil {
		return err
	}
	d.CurrentOrderID = &orderID
	return nil
}
