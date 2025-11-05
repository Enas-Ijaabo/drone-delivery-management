package usecase

import (
	"context"
	"errors"
	"strconv"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/Enas-Ijaabo/drone-delivery-management/internal/repo"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

var ErrInvalidCredentials = errors.New("invalid credentials")

type UsersAuthRepo interface {
	GetAuthByName(ctx context.Context, name string) (*model.User, string, error)
}

type AuthUsecase struct {
	users    UsersAuthRepo
	secret   []byte
	ttl      time.Duration
	issuer   string
	audience string
}

func NewAuthUsecase(users UsersAuthRepo, secret []byte, ttl time.Duration, issuer, audience string) *AuthUsecase {
	return &AuthUsecase{users: users, secret: secret, ttl: ttl, issuer: issuer, audience: audience}
}

func (u *AuthUsecase) IssueToken(ctx context.Context, login model.Login) (*string, *time.Time, *model.User, error) {
	user, passwordHash, err := u.users.GetAuthByName(ctx, login.Name)
	if err != nil {
		if errors.Is(err, repo.ErrUserNotFound) {
			return nil, nil, nil, ErrInvalidCredentials
		}
		return nil, nil, nil, err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(login.Password)); err != nil {
		return nil, nil, nil, ErrInvalidCredentials
	}

	now := time.Now().UTC()
	signed, exp, err := u.signToken(*user, now)
	if err != nil {
		return nil, nil, nil, err
	}

	return &signed, &exp, user, nil
}

func (u *AuthUsecase) signToken(user model.User, now time.Time) (string, time.Time, error) {
	ttl := u.ttl
	if ttl <= 0 {
		ttl = time.Hour
	}
	exp := now.Add(ttl)
	claims := jwt.MapClaims{
		"sub":  strconv.FormatInt(user.ID, 10),
		"name": user.Name,
		"role": string(user.Role),
		"iss":  u.issuer,
		"aud":  u.audience,
		"iat":  now.Unix(),
		"exp":  exp.Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(u.secret)
	if err != nil {
		return "", time.Time{}, err
	}
	return signed, exp, nil
}
