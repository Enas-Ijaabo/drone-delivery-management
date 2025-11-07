package usecase

import (
	"context"
	"database/sql"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
)

type OrderRepo interface {
	Insert(ctx context.Context, order *model.Order) (*model.Order, error)
	GetByIDForUpdate(ctx context.Context, tx *sql.Tx, id int64) (*model.Order, error)
	UpdateStatusTx(ctx context.Context, tx *sql.Tx, order *model.Order) (*model.Order, error)
	BeginTx(ctx context.Context) (*sql.Tx, error)
}

type OrderUsecase struct {
	orderRepo OrderRepo
}

func NewOrderUsecase(orderRepo OrderRepo) *OrderUsecase {
	return &OrderUsecase{orderRepo: orderRepo}
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

	updatedOrder, err := uc.orderRepo.UpdateStatusTx(ctx, tx, order)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return updatedOrder, nil
}
