package repo

import (
	"context"
	"database/sql"
	"errors"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
)

const (
	getDroneByIDQuery = `
		SELECT u.id, COALESCE(ds.status, 'idle'), ds.current_order_id, 
		       COALESCE(ds.lat, 0.0), COALESCE(ds.lng, 0.0), 
		       ds.last_heartbeat_at, u.created_at, u.updated_at
		FROM users u
		LEFT JOIN drone_status ds ON u.id = ds.drone_id
		WHERE u.id = ? AND u.type = 'drone'
	`
)

type droneDBO struct {
	ID             int64         `dbo:"id"`
	Status         string        `dbo:"status"`
	CurrentOrderID sql.NullInt64 `dbo:"current_order_id"`
	Lat            float64       `dbo:"lat"`
	Lng            float64       `dbo:"lng"`
	LastHeartbeat  sql.NullTime  `dbo:"last_heartbeat"`
	CreatedAt      sql.NullTime  `dbo:"created_at"`
	UpdatedAt      sql.NullTime  `dbo:"updated_at"`
}

type DroneRepo struct {
	db *sql.DB
}

func NewDroneRepo(db *sql.DB) *DroneRepo {
	return &DroneRepo{db: db}
}

func (r *DroneRepo) GetByID(ctx context.Context, id int64) (*model.Drone, error) {
	var dbo droneDBO
	err := r.db.QueryRowContext(ctx, getDroneByIDQuery, id).Scan(
		&dbo.ID,
		&dbo.Status,
		&dbo.CurrentOrderID,
		&dbo.Lat,
		&dbo.Lng,
		&dbo.LastHeartbeat,
		&dbo.CreatedAt,
		&dbo.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrDroneNotFound()
		}
		return nil, err
	}

	return dbo.toModel(), nil
}

func (dbo *droneDBO) toModel() *model.Drone {
	drone := &model.Drone{
		ID:     dbo.ID,
		Status: model.DroneStatus(dbo.Status),
		Lat:    dbo.Lat,
		Lng:    dbo.Lng,
	}

	if dbo.CurrentOrderID.Valid {
		drone.CurrentOrderID = &dbo.CurrentOrderID.Int64
	}

	if dbo.LastHeartbeat.Valid {
		drone.LastHeartbeat = &dbo.LastHeartbeat.Time
	}

	if dbo.CreatedAt.Valid {
		drone.CreatedAt = dbo.CreatedAt.Time
	}

	if dbo.UpdatedAt.Valid {
		drone.UpdatedAt = dbo.UpdatedAt.Time
	}

	return drone
}
