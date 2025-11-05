package repo

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
)

type userDBO struct {
	ID           int64     `dbo:"id"`
	Name         string    `dbo:"name"`
	PasswordHash string    `dbo:"password_hash"`
	Type         string    `dbo:"type"`
	CreatedAt    time.Time `dbo:"created_at"`
	UpdatedAt    time.Time `dbo:"updated_at"`
}

var ErrUserNotFound = errors.New("user not found")

type SQLUsersRepo struct {
	DB *sql.DB
}

func NewUsersRepo(db *sql.DB) *SQLUsersRepo { return &SQLUsersRepo{DB: db} }

func (r *SQLUsersRepo) GetAuthByName(ctx context.Context, name string) (*model.User, string, error) {
	const q = `SELECT id, name, password_hash, type, created_at, updated_at FROM users WHERE name = ? LIMIT 1`
	row := r.DB.QueryRowContext(ctx, q, name)
	var dbo userDBO
	if err := row.Scan(&dbo.ID, &dbo.Name, &dbo.PasswordHash, &dbo.Type, &dbo.CreatedAt, &dbo.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, "", ErrUserNotFound
		}
		return nil, "", err
	}
	return &model.User{
		ID:        dbo.ID,
		Name:      dbo.Name,
		Role:      model.Role(dbo.Type),
		CreatedAt: dbo.CreatedAt,
		UpdatedAt: dbo.UpdatedAt,
	}, dbo.PasswordHash, nil
}

func (r *SQLUsersRepo) Create(ctx context.Context, u model.User, passwordHash string) (int64, error) {
	const q = `INSERT INTO users (name, password_hash, type) VALUES (?, ?, ?)`
	res, err := r.DB.ExecContext(ctx, q, u.Name, passwordHash, string(u.Role))
	if err != nil {
		return 0, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return 0, err
	}
	return id, nil
}
