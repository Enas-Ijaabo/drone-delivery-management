package usecase

import (
	"context"
	"database/sql"
	"log"
	"time"

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
	FindNearestIdle(ctx context.Context, lat, lng float64) (*model.Drone, error)
}

type AssignmentNotifier interface {
	NotifyAssignment(ctx context.Context, notice model.AssignmentNotice) error
}

type OrderUsecase struct {
	orderRepo  OrderRepo
	droneRepo  DroneRepo
	notifier   AssignmentNotifier
	assignTTL  time.Duration
	workerPool chan struct{}
}

func NewOrderUsecase(orderRepo OrderRepo, droneRepo DroneRepo, notifier AssignmentNotifier) *OrderUsecase {
	return &OrderUsecase{
		orderRepo:  orderRepo,
		droneRepo:  droneRepo,
		notifier:   notifier,
		assignTTL:  5 * time.Second,
		workerPool: make(chan struct{}, 4),
	}
}

func (uc *OrderUsecase) CreateOrder(ctx context.Context, req model.CreateOrderRequest) (*model.Order, error) {
	order := model.NewOrder(req)

	created, err := uc.orderRepo.Insert(ctx, order)
	if err != nil {
		return nil, err
	}

	uc.triggerAssignment(*created)

	return created, nil
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

	uc.triggerAssignmentIfPending(updatedOrder)

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

func (uc *OrderUsecase) UpdateRoute(ctx context.Context, orderID int64, req model.UpdateRouteRequest) (*model.Order, error) {
	tx, err := uc.orderRepo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	order, err := uc.orderRepo.GetByIDForUpdate(ctx, tx, orderID)
	if err != nil {
		return nil, err
	}

	if err := order.UpdateRoute(req); err != nil {
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

func (uc *OrderUsecase) AssignOrder(ctx context.Context, order model.Order) error {
	if uc.notifier == nil {
		return nil
	}

	drone, err := uc.droneRepo.FindNearestIdle(ctx, order.PickupLat, order.PickupLng)
	if err != nil {
		return err
	}

	notice := model.NewAssignmentNotice(order, *drone)
	return uc.notifier.NotifyAssignment(ctx, notice)
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

func (uc *OrderUsecase) triggerAssignment(order model.Order) {
	if uc.notifier == nil {
		return
	}

	select {
	case uc.workerPool <- struct{}{}:
	default:
		// pool full; skip assignment attempt to avoid unbounded goroutines
		return
	}

	go func(o model.Order) {
		defer func() { <-uc.workerPool }()

		ctx, cancel := context.WithTimeout(context.Background(), uc.assignTTL)
		defer cancel()

		if err := uc.AssignOrder(ctx, o); err != nil {
			log.Printf("assign order %d failed: %v", o.ID, err)
		}
	}(order)
}

func (uc *OrderUsecase) DeliverOrder(ctx context.Context, droneID, orderID int64) (*model.Order, error) {
	tx, err := uc.orderRepo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	order, err := uc.orderRepo.GetByIDForUpdate(ctx, tx, orderID)
	if err != nil {
		return nil, err
	}

	if err := order.IsAssignedTo(droneID); err != nil {
		return nil, err
	}

	drone, err := uc.droneRepo.GetByIDForUpdate(ctx, tx, droneID)
	if err != nil {
		return nil, err
	}

	if err := order.Deliver(); err != nil {
		return nil, err
	}

	if err := drone.CompleteDelivery(); err != nil {
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

func (uc *OrderUsecase) PickupOrder(ctx context.Context, droneID, orderID int64) (*model.Order, error) {
	tx, err := uc.orderRepo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	order, err := uc.orderRepo.GetByIDForUpdate(ctx, tx, orderID)
	if err != nil {
		return nil, err
	}

	if err := order.IsAssignedTo(droneID); err != nil {
		return nil, err
	}

	drone, err := uc.droneRepo.GetByIDForUpdate(ctx, tx, droneID)
	if err != nil {
		return nil, err
	}

	if err := order.Pickup(); err != nil {
		return nil, err
	}

	if err := drone.StartDelivery(); err != nil {
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

func (uc *OrderUsecase) FailOrder(ctx context.Context, droneID, orderID int64) (*model.Order, error) {
	tx, err := uc.orderRepo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	order, err := uc.orderRepo.GetByIDForUpdate(ctx, tx, orderID)
	if err != nil {
		return nil, err
	}

	if err := order.IsAssignedTo(droneID); err != nil {
		return nil, err
	}

	drone, err := uc.droneRepo.GetByIDForUpdate(ctx, tx, droneID)
	if err != nil {
		return nil, err
	}

	if err := order.Fail(); err != nil {
		return nil, err
	}

	if err := drone.FailDelivery(); err != nil {
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

	uc.triggerAssignmentIfPending(updatedOrder)

	return updatedOrder, nil
}

func (uc *OrderUsecase) triggerAssignmentIfPending(order *model.Order) {
	if order == nil {
		return
	}
	if needsAssignment(order.Status) {
		uc.triggerAssignment(*order)
	}
}

func needsAssignment(status model.OrderStatus) bool {
	return status == model.OrderPending || status == model.OrderHandoffPending
}

func (uc *OrderUsecase) ScheduleAssignment(order model.Order) {
	uc.triggerAssignment(order)
}
