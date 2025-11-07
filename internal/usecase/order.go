package usecase

import (
	"context"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
)

type OrderRepo interface {
	Insert(ctx context.Context, order *model.Order) (*model.Order, error)
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
