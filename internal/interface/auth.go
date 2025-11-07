package iface

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/Enas-Ijaabo/drone-delivery-management/internal/repo"
	"github.com/Enas-Ijaabo/drone-delivery-management/internal/usecase"
	"github.com/gin-gonic/gin"
)

type loginRequest struct {
	Name     string `json:"name" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type userResponse struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
	Type string `json:"type"`
}

type loginResponse struct {
	AccessToken string       `json:"access_token"`
	TokenType   string       `json:"token_type"`
	ExpiresIn   int64        `json:"expires_in"`
	User        userResponse `json:"user"`
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
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": "name and password required"})
		return
	}

	login := toLoginModel(req)
	tok, exp, usr, err := h.uc.IssueToken(c.Request.Context(), login)
	if err != nil {
		// Check for repo errors (user not found)
		var repoErr *repo.RepoError
		if errors.As(err, &repoErr) && repoErr.Code == repo.ErrCodeUserNotFound {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized", "message": "invalid credentials"})
			return
		}
		// Check for invalid credentials
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

func toLoginModel(req loginRequest) model.Login {
	return model.Login{
		Name:     req.Name,
		Password: req.Password,
	}
}

func toLoginResponse(token string, exp time.Time, u model.User) loginResponse {
	now := time.Now().UTC()
	expiresIn := exp.Unix() - now.Unix()
	if expiresIn < 0 {
		expiresIn = 0
	}
	return loginResponse{
		AccessToken: token,
		TokenType:   "bearer",
		ExpiresIn:   expiresIn,
		User:        toUserResponse(u),
	}
}

func toUserResponse(u model.User) userResponse {
	return userResponse{
		ID:   u.ID,
		Name: u.Name,
		Type: string(u.Role),
	}
}
