package model

import (
	"time"
)

type DroneHeartbeat struct {
	Lat float64
	Lng float64
}

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
		DroneBroken,
	},
	DroneReserved: {
		DroneDelivering,
		DroneIdle,
		DroneBroken,
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

func (d *Drone) CompleteDelivery() error {
	if err := d.UpdateStatus(DroneIdle); err != nil {
		return err
	}
	d.CurrentOrderID = nil
	return nil
}

func (d *Drone) StartDelivery() error {
	return d.UpdateStatus(DroneDelivering)
}

func (d *Drone) FailDelivery() error {
	if err := d.UpdateStatus(DroneIdle); err != nil {
		return err
	}
	d.CurrentOrderID = nil
	return nil
}

func (d *Drone) IsBroken() bool {
	return d.Status == DroneBroken
}

func (d *Drone) Validate() error {
	if d.Lat < -90 || d.Lat > 90 {
		return ErrInvalidLatitude(d.Lat)
	}
	if d.Lng < -180 || d.Lng > 180 {
		return ErrInvalidLongitude(d.Lng)
	}
	return nil
}

func (d *Drone) ApplyHeartbeat(update DroneHeartbeat, now time.Time) error {
	if err := d.Validate(); err != nil {
		return err
	}

	d.Lat = update.Lat
	d.Lng = update.Lng
	d.LastHeartbeat = &now

	return nil
}

func (d *Drone) ReportBroken(location DroneHeartbeat) error {
	if location.Lat < -90 || location.Lat > 90 {
		return ErrInvalidLatitude(location.Lat)
	}
	if location.Lng < -180 || location.Lng > 180 {
		return ErrInvalidLongitude(location.Lng)
	}

	if d.Status != DroneBroken {
		if err := d.UpdateStatus(DroneBroken); err != nil {
			return err
		}
	}

	d.Lat = location.Lat
	d.Lng = location.Lng
	d.CurrentOrderID = nil

	return nil
}

func (d *Drone) ReportFixed(location DroneHeartbeat) error {
	if location.Lat < -90 || location.Lat > 90 {
		return ErrInvalidLatitude(location.Lat)
	}
	if location.Lng < -180 || location.Lng > 180 {
		return ErrInvalidLongitude(location.Lng)
	}

	if d.Status != DroneIdle {
		if err := d.UpdateStatus(DroneIdle); err != nil {
			return err
		}
	}

	d.Lat = location.Lat
	d.Lng = location.Lng
	d.CurrentOrderID = nil

	return nil
}
