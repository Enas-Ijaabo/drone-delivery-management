package iface

import (
	"github.com/gin-gonic/gin"
)

func NewRouter(authHandler *AuthHandler, authMW gin.HandlerFunc) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// Public health
	r.GET("/health", HealthHandler)

	// Auth endpoints
	r.POST("/auth/token", authHandler.AuthTokenHandler)

	return r
}
