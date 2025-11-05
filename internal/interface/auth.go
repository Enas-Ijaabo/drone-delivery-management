package iface

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/Enas-Ijaabo/drone-delivery-management/internal/usecase"
	"github.com/gin-gonic/gin"
)

type LoginRequest struct {
	Name     string `json:"name" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type UserResponse struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
	Type string `json:"type"`
}

type LoginResponse struct {
	AccessToken string       `json:"access_token"`
	TokenType   string       `json:"token_type"`
	ExpiresIn   int64        `json:"expires_in"`
	User        UserResponse `json:"user"`
}

type AuthUsecase interface {
	IssueToken(ctx context.Context, login model.Login) (*string, *time.Time, *model.User, error)
}

type AuthHandler struct {
	uc AuthUsecase
}

func NewAuthHandler(uc AuthUsecase) *AuthHandler {
	return &AuthHandler{uc: uc}
}

func (h *AuthHandler) AuthTokenHandler(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "name and password required"})
		return
	}

	login := toLoginModel(req)
	tok, exp, usr, err := h.uc.IssueToken(c.Request.Context(), login)
	if err != nil {
		if errors.Is(err, usecase.ErrInvalidCredentials) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid credentials"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal_error"})
		return
	}

	if tok == nil || exp == nil || usr == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal_error"})
		return
	}

	c.JSON(http.StatusOK, toLoginResponse(*tok, *exp, *usr))
}

func toLoginModel(req LoginRequest) model.Login {
	return model.Login{
		Name:     req.Name,
		Password: req.Password,
	}
}

func toLoginResponse(token string, exp time.Time, u model.User) LoginResponse {
	now := time.Now().UTC()
	expiresIn := exp.Unix() - now.Unix()
	if expiresIn < 0 {
		expiresIn = 0
	}
	return LoginResponse{
		AccessToken: token,
		TokenType:   "bearer",
		ExpiresIn:   expiresIn,
		User:        toUserResponse(u),
	}
}

func toUserResponse(u model.User) UserResponse {
	return UserResponse{
		ID:   u.ID,
		Name: u.Name,
		Type: string(u.Role),
	}
}
