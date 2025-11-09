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
	getDroneByIDForUpdateQuery = `
		SELECT u.id, COALESCE(ds.status, 'idle'), ds.current_order_id, 
		       COALESCE(ds.lat, 0.0), COALESCE(ds.lng, 0.0), 
		       ds.last_heartbeat_at, u.created_at, u.updated_at
		FROM users u
		LEFT JOIN drone_status ds ON u.id = ds.drone_id
		WHERE u.id = ? AND u.type = 'drone'
		FOR UPDATE
	`
	findNearestIdleQuery = `
		SELECT u.id, ds.status, ds.current_order_id,
		       ds.lat, ds.lng,
		       ds.last_heartbeat_at, u.created_at, u.updated_at
		FROM drone_status ds
		JOIN users u ON u.id = ds.drone_id
		WHERE ds.status = 'idle'
		ORDER BY ST_Distance_Sphere(
			ds.location,
			ST_SRID(POINT(?, ?), 4326)
		), ds.drone_id
		LIMIT 1
	`
	updateDroneQuery = `
		UPDATE drone_status 
		SET status = ?, current_order_id = ?, lat = ?, lng = ?, location = ST_SRID(POINT(?, ?), 4326), last_heartbeat_at = ?, updated_at = NOW()
		WHERE drone_id = ?
	`
)

type droneDBO struct {
	ID             int64         `dbo:"id"`
	Status         string        `dbo:"status"`
	CurrentOrderID sql.NullInt64 `dbo:"current_order_id"`
	Lat            float64       `dbo:"lat"`
	Lng            float64       `dbo:"lng"`
	LastHeartbeat  sql.NullTime  `dbo:"last_heartbeat_at"`
	CreatedAt      sql.NullTime  `dbo:"created_at"`
	UpdatedAt      sql.NullTime  `dbo:"updated_at"`
}

type DroneRepo struct {
	db *sql.DB
}

func NewDroneRepo(db *sql.DB) *DroneRepo {
	return &DroneRepo{db: db}
}

func (r *DroneRepo) BeginTx(ctx context.Context) (*sql.Tx, error) {
	return r.db.BeginTx(ctx, nil)
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

func (r *DroneRepo) GetByIDForUpdate(ctx context.Context, tx *sql.Tx, id int64) (*model.Drone, error) {
	var dbo droneDBO
	err := tx.QueryRowContext(ctx, getDroneByIDForUpdateQuery, id).Scan(
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

func (r *DroneRepo) UpdateTx(ctx context.Context, tx *sql.Tx, drone *model.Drone) (*model.Drone, error) {
	dbo := toDroneDBO(drone)

	_, err := tx.ExecContext(ctx, updateDroneQuery,
		dbo.Status,
		dbo.CurrentOrderID,
		dbo.Lat,
		dbo.Lng,
		dbo.Lng,
		dbo.Lat,
		dbo.LastHeartbeat,
		dbo.ID)
	if err != nil {
		return nil, err
	}

	return r.GetByIDForUpdate(ctx, tx, drone.ID)
}

func (r *DroneRepo) FindNearestIdle(ctx context.Context, lat, lng float64) (*model.Drone, error) {
	var dbo droneDBO
	err := r.db.QueryRowContext(ctx, findNearestIdleQuery, lng, lat).Scan(
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

func toDroneDBO(drone *model.Drone) droneDBO {
	dbo := droneDBO{
		ID:     drone.ID,
		Status: string(drone.Status),
		Lat:    drone.Lat,
		Lng:    drone.Lng,
	}

	if drone.CurrentOrderID != nil {
		dbo.CurrentOrderID = sql.NullInt64{Int64: *drone.CurrentOrderID, Valid: true}
	}

	if drone.LastHeartbeat != nil {
		dbo.LastHeartbeat = sql.NullTime{Time: *drone.LastHeartbeat, Valid: true}
	}

	if !drone.CreatedAt.IsZero() {
		dbo.CreatedAt = sql.NullTime{Time: drone.CreatedAt, Valid: true}
	}

	if !drone.UpdatedAt.IsZero() {
		dbo.UpdatedAt = sql.NullTime{Time: drone.UpdatedAt, Valid: true}
	}

	return dbo
}
