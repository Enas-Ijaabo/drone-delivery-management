package usecase

import (
	"context"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
)

type AssignmentScheduler interface {
	ScheduleAssignment(order model.Order)
}

type DroneOpsUsecase struct {
	droneRepo DroneRepo
	orderRepo OrderRepo
	scheduler AssignmentScheduler
}

func NewDroneOpsUsecase(droneRepo DroneRepo, orderRepo OrderRepo, scheduler AssignmentScheduler) *DroneOpsUsecase {
	return &DroneOpsUsecase{
		droneRepo: droneRepo,
		orderRepo: orderRepo,
		scheduler: scheduler,
	}
}

func (uc *DroneOpsUsecase) ReportBroken(ctx context.Context, actorID, droneID int64, actorRole model.Role, location model.DroneHeartbeat) (*model.Drone, *model.Order, error) {
	if actorRole.IsDrone() && actorID != droneID {
		return nil, nil, model.ErrDroneActionNotAllowed()
	}

	tx, err := uc.droneRepo.BeginTx(ctx)
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback()

	drone, err := uc.droneRepo.GetByIDForUpdate(ctx, tx, droneID)
	if err != nil {
		return nil, nil, err
	}
	previousOrderID := drone.CurrentOrderID

	if err := drone.ReportBroken(location); err != nil {
		return nil, nil, err
	}

	var updatedOrder *model.Order
	var needsAssignment bool
	if previousOrderID != nil {
		order, err := uc.orderRepo.GetByIDForUpdate(ctx, tx, *previousOrderID)
		if err != nil {
			return nil, nil, err
		}

		if err := order.IsAssignedTo(drone.ID); err != nil {
			return nil, nil, err
		}

		if needsAssignment = order.HandoffOrder(drone.Lat, drone.Lng); needsAssignment {
			updatedOrder, err = uc.orderRepo.UpdateTx(ctx, tx, order)
			if err != nil {
				return nil, nil, err
			}
		}
	}

	updatedDrone, err := uc.droneRepo.UpdateTx(ctx, tx, drone)
	if err != nil {
		return nil, nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, nil, err
	}

	if needsAssignment && updatedOrder != nil && uc.scheduler != nil {
		uc.scheduler.ScheduleAssignment(*updatedOrder)
	}

	return updatedDrone, updatedOrder, nil
}

func (uc *DroneOpsUsecase) ReportFixed(ctx context.Context, actorID, droneID int64, actorRole model.Role, location model.DroneHeartbeat) (*model.Drone, error) {
	if actorRole.IsDrone() && actorID != droneID {
		return nil, model.ErrDroneActionNotAllowed()
	}

	tx, err := uc.droneRepo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	drone, err := uc.droneRepo.GetByIDForUpdate(ctx, tx, droneID)
	if err != nil {
		return nil, err
	}

	if err := drone.ReportFixed(location); err != nil {
		return nil, err
	}

	updatedDrone, err := uc.droneRepo.UpdateTx(ctx, tx, drone)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return updatedDrone, nil
}
