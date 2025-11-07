package iface

import (
	"github.com/gin-gonic/gin"
)

func NewRouter(authHandler *AuthHandler, orderHandler *OrderHandler, authMW gin.HandlerFunc) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery(), ErrorHandlerMiddleware())

	// Public health
	r.GET("/health", HealthHandler)

	// Auth endpoints
	r.POST("/auth/token", authHandler.AuthTokenHandler)

	// Enduser order endpoints
	enduser := r.Group("/orders")
	enduser.Use(authMW, RequireRoles("enduser"))
	{
		enduser.POST("", orderHandler.CreateOrder)
		enduser.POST("/:id/cancel", orderHandler.CancelOrder)
	}

	return r
}
