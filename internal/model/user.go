package model

import "time"

type Role string

const (
	RoleAdmin   Role = "admin"
	RoleEndUser Role = "enduser"
	RoleDrone   Role = "drone"
)

func (r Role) IsDrone() bool {
	return r == RoleDrone
}

type User struct {
	ID        int64
	Name      string
	Role      Role
	CreatedAt time.Time
	UpdatedAt time.Time
}
