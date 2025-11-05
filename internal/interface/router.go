package iface

import (
	"github.com/gin-gonic/gin"
)

func NewRouter(authHandler *AuthHandler) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	r.GET("/health", HealthHandler)
	r.POST("/auth/token", authHandler.AuthTokenHandler)

	return r
}
