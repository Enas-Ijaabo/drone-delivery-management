package repo

import (
	"context"
	"database/sql"
	"errors"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/go-sql-driver/mysql"
)

const (
	insertOrderQuery = `
		INSERT INTO orders (enduser_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, status)
		VALUES (?, ?, ?, ?, ?, ?)
	`
	getOrderByIDQuery = `
		SELECT id, enduser_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, 
		       status, assigned_drone_id, handoff_lat, handoff_lng, 
		       created_at, updated_at, canceled_at
		FROM orders
		WHERE id = ?
	`
	getOrderByIDForUpdateQuery = `
		SELECT id, enduser_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, 
		       status, assigned_drone_id, handoff_lat, handoff_lng, 
		       created_at, updated_at, canceled_at
		FROM orders
		WHERE id = ? FOR UPDATE
	`
	updateOrderStatusQuery = `
		UPDATE orders 
		SET status = ?, updated_at = NOW(), canceled_at = CASE WHEN ? = 'canceled' THEN NOW() ELSE canceled_at END
		WHERE id = ?
	`
)

type orderDBO struct {
	ID              int64           `dbo:"id"`
	EnduserID       int64           `dbo:"enduser_id"`
	PickupLat       float64         `dbo:"pickup_lat"`
	PickupLng       float64         `dbo:"pickup_lng"`
	DropoffLat      float64         `dbo:"dropoff_lat"`
	DropoffLng      float64         `dbo:"dropoff_lng"`
	Status          string          `dbo:"status"`
	AssignedDroneID sql.NullInt64   `dbo:"assigned_drone_id"`
	HandoffLat      sql.NullFloat64 `dbo:"handoff_lat"`
	HandoffLng      sql.NullFloat64 `dbo:"handoff_lng"`
	CreatedAt       sql.NullTime    `dbo:"created_at"`
	UpdatedAt       sql.NullTime    `dbo:"updated_at"`
	CanceledAt      sql.NullTime    `dbo:"canceled_at"`
}

type OrderRepo struct {
	db *sql.DB
}

func NewOrderRepo(db *sql.DB) *OrderRepo {
	return &OrderRepo{db: db}
}

func (r *OrderRepo) BeginTx(ctx context.Context) (*sql.Tx, error) {
	return r.db.BeginTx(ctx, nil)
}

func (r *OrderRepo) Insert(ctx context.Context, order *model.Order) (*model.Order, error) {
	dbo := toOrderDBO(order)

	result, err := r.db.ExecContext(ctx, insertOrderQuery,
		dbo.EnduserID,
		dbo.PickupLat,
		dbo.PickupLng,
		dbo.DropoffLat,
		dbo.DropoffLng,
		dbo.Status,
	)
	if err != nil {
		if isFKConstraintError(err) {
			return nil, ErrInvalidEnduserID()
		}
		return nil, err
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, err
	}

	return r.GetByID(ctx, id)
}

func (r *OrderRepo) GetByID(ctx context.Context, id int64) (*model.Order, error) {
	var dbo orderDBO
	err := r.db.QueryRowContext(ctx, getOrderByIDQuery, id).Scan(
		&dbo.ID,
		&dbo.EnduserID,
		&dbo.PickupLat,
		&dbo.PickupLng,
		&dbo.DropoffLat,
		&dbo.DropoffLng,
		&dbo.Status,
		&dbo.AssignedDroneID,
		&dbo.HandoffLat,
		&dbo.HandoffLng,
		&dbo.CreatedAt,
		&dbo.UpdatedAt,
		&dbo.CanceledAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrOrderNotFound()
		}
		return nil, err
	}

	return toOrderModel(dbo), nil
}

func (r *OrderRepo) GetByIDForUpdate(ctx context.Context, tx *sql.Tx, id int64) (*model.Order, error) {
	var dbo orderDBO
	err := tx.QueryRowContext(ctx, getOrderByIDForUpdateQuery, id).Scan(
		&dbo.ID,
		&dbo.EnduserID,
		&dbo.PickupLat,
		&dbo.PickupLng,
		&dbo.DropoffLat,
		&dbo.DropoffLng,
		&dbo.Status,
		&dbo.AssignedDroneID,
		&dbo.HandoffLat,
		&dbo.HandoffLng,
		&dbo.CreatedAt,
		&dbo.UpdatedAt,
		&dbo.CanceledAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrOrderNotFound()
		}
		return nil, err
	}
	return toOrderModel(dbo), nil
}

func (r *OrderRepo) UpdateStatusTx(ctx context.Context, tx *sql.Tx, order *model.Order) (*model.Order, error) {
	_, err := tx.ExecContext(ctx, updateOrderStatusQuery, string(order.Status), string(order.Status), order.ID)
	if err != nil {
		return nil, err
	}
	return r.GetByIDForUpdate(ctx, tx, order.ID)
}

func toOrderModel(dbo orderDBO) *model.Order {
	o := &model.Order{
		ID:         dbo.ID,
		EnduserID:  dbo.EnduserID,
		PickupLat:  dbo.PickupLat,
		PickupLng:  dbo.PickupLng,
		DropoffLat: dbo.DropoffLat,
		DropoffLng: dbo.DropoffLng,
		Status:     model.OrderStatus(dbo.Status),
	}

	if dbo.AssignedDroneID.Valid {
		o.AssignedDroneID = &dbo.AssignedDroneID.Int64
	}
	if dbo.HandoffLat.Valid {
		o.HandoffLat = &dbo.HandoffLat.Float64
	}
	if dbo.HandoffLng.Valid {
		o.HandoffLng = &dbo.HandoffLng.Float64
	}
	if dbo.CreatedAt.Valid {
		o.CreatedAt = dbo.CreatedAt.Time
	}
	if dbo.UpdatedAt.Valid {
		o.UpdatedAt = dbo.UpdatedAt.Time
	}
	if dbo.CanceledAt.Valid {
		o.CanceledAt = &dbo.CanceledAt.Time
	}

	return o
}

func toOrderDBO(order *model.Order) orderDBO {
	dbo := orderDBO{
		ID:         order.ID,
		EnduserID:  order.EnduserID,
		PickupLat:  order.PickupLat,
		PickupLng:  order.PickupLng,
		DropoffLat: order.DropoffLat,
		DropoffLng: order.DropoffLng,
		Status:     string(order.Status),
	}

	if order.AssignedDroneID != nil {
		dbo.AssignedDroneID = sql.NullInt64{Int64: *order.AssignedDroneID, Valid: true}
	}
	if order.HandoffLat != nil {
		dbo.HandoffLat = sql.NullFloat64{Float64: *order.HandoffLat, Valid: true}
	}
	if order.HandoffLng != nil {
		dbo.HandoffLng = sql.NullFloat64{Float64: *order.HandoffLng, Valid: true}
	}
	if !order.CreatedAt.IsZero() {
		dbo.CreatedAt = sql.NullTime{Time: order.CreatedAt, Valid: true}
	}
	if !order.UpdatedAt.IsZero() {
		dbo.UpdatedAt = sql.NullTime{Time: order.UpdatedAt, Valid: true}
	}
	if order.CanceledAt != nil {
		dbo.CanceledAt = sql.NullTime{Time: *order.CanceledAt, Valid: true}
	}

	return dbo
}

func isFKConstraintError(err error) bool {
	var mysqlErr *mysql.MySQLError
	if errors.As(err, &mysqlErr) {
		return mysqlErr.Number == 1452
	}
	return false
}
