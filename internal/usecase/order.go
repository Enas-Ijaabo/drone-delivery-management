package usecase

import (
	"context"
	"database/sql"
	"log"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
)

type OrderRepo interface {
	Insert(ctx context.Context, order *model.Order) (*model.Order, error)
	GetByID(ctx context.Context, id int64) (*model.Order, error)
	GetByIDForUpdate(ctx context.Context, tx *sql.Tx, id int64) (*model.Order, error)
	UpdateTx(ctx context.Context, tx *sql.Tx, order *model.Order) (*model.Order, error)
	BeginTx(ctx context.Context) (*sql.Tx, error)
}

type DroneRepo interface {
	GetByID(ctx context.Context, id int64) (*model.Drone, error)
	GetByIDForUpdate(ctx context.Context, tx *sql.Tx, id int64) (*model.Drone, error)
	UpdateTx(ctx context.Context, tx *sql.Tx, drone *model.Drone) (*model.Drone, error)
	BeginTx(ctx context.Context) (*sql.Tx, error)
}

type OrderUsecase struct {
	orderRepo OrderRepo
	droneRepo DroneRepo
}

func NewOrderUsecase(orderRepo OrderRepo, droneRepo DroneRepo) *OrderUsecase {
	return &OrderUsecase{
		orderRepo: orderRepo,
		droneRepo: droneRepo,
	}
}

func (uc *OrderUsecase) CreateOrder(ctx context.Context, req model.CreateOrderRequest) (*model.Order, error) {
	order := model.NewOrder(req)

	return uc.orderRepo.Insert(ctx, order)
}

func (uc *OrderUsecase) CancelOrder(ctx context.Context, userID, orderID int64) (*model.Order, error) {
	tx, err := uc.orderRepo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	order, err := uc.orderRepo.GetByIDForUpdate(ctx, tx, orderID)
	if err != nil {
		return nil, err
	}

	if err := order.BelongsTo(userID); err != nil {
		return nil, err
	}

	if err := order.UpdateStatus(model.OrderCanceled); err != nil {
		return nil, err
	}

	updatedOrder, err := uc.orderRepo.UpdateTx(ctx, tx, order)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return updatedOrder, nil
}

func (uc *OrderUsecase) GetOrder(ctx context.Context, userID, orderID int64) (*model.OrderDetails, error) {
	order, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}

	if err := order.BelongsTo(userID); err != nil {
		return nil, err
	}

	var drone *model.Drone
	if order.AssignedDroneID != nil {
		drone, err = uc.droneRepo.GetByID(ctx, *order.AssignedDroneID)
		if err != nil {
			log.Printf("failed to get drone %d for order %d: %v", *order.AssignedDroneID, order.ID, err)
			drone = nil
		}
	}

	details := model.NewOrderDetails(*order, drone)
	return &details, nil
}

func (uc *OrderUsecase) ReserveOrder(ctx context.Context, droneID, orderID int64) (*model.Order, error) {
	tx, err := uc.orderRepo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	order, err := uc.orderRepo.GetByIDForUpdate(ctx, tx, orderID)
	if err != nil {
		return nil, err
	}

	drone, err := uc.droneRepo.GetByIDForUpdate(ctx, tx, droneID)
	if err != nil {
		return nil, err
	}

	if err := order.Reserve(droneID); err != nil {
		return nil, err
	}

	if err := drone.Reserve(orderID); err != nil {
		return nil, err
	}

	updatedOrder, err := uc.orderRepo.UpdateTx(ctx, tx, order)
	if err != nil {
		return nil, err
	}

	_, err = uc.droneRepo.UpdateTx(ctx, tx, drone)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return updatedOrder, nil
}
