package usecase

import (
	"context"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
)

type DroneUsecase struct {
	droneRepo DroneRepo
}

func NewDroneUsecase(droneRepo DroneRepo) *DroneUsecase {
	return &DroneUsecase{droneRepo: droneRepo}
}

func (uc *DroneUsecase) Heartbeat(ctx context.Context, droneID int64, hb model.DroneHeartbeat) (*model.Drone, error) {
	tx, err := uc.droneRepo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	drone, err := uc.droneRepo.GetByIDForUpdate(ctx, tx, droneID)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	if err := drone.ApplyHeartbeat(hb, now); err != nil {
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
