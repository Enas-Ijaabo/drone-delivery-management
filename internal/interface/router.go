package iface

import (
	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

func NewRouter(authHandler *AuthHandler, orderHandler *OrderHandler, droneHandler *DroneHandler, droneWSHandler *DroneWSHandler, authMW gin.HandlerFunc) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery(), ErrorHandlerMiddleware())

	// Public health
	r.GET("/health", HealthHandler)

	// Swagger documentation
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	// Auth endpoints
	r.POST("/auth/token", authHandler.AuthTokenHandler)

	// Enduser order endpoints
	enduser := r.Group("/orders")
	enduser.Use(authMW, RequireRoles("enduser"))
	{
		enduser.POST("", orderHandler.CreateOrder)
		enduser.GET("/:id", orderHandler.GetOrder)
		enduser.POST("/:id/cancel", orderHandler.CancelOrder)
	}

	// Drone order endpoints
	drone := r.Group("/orders")
	drone.Use(authMW, RequireRoles("drone"))
	{
		drone.POST("/:id/reserve", orderHandler.ReserveOrder)
		drone.POST("/:id/pickup", orderHandler.PickupOrder)
		drone.POST("/:id/deliver", orderHandler.DeliverOrder)
		drone.POST("/:id/fail", orderHandler.FailOrder)
	}

	ws := r.Group("/ws")
	ws.Use(authMW, RequireRoles("drone"))
	{
		ws.GET("/heartbeat", droneWSHandler.HandleHeartbeat)
	}

	droneMgmt := r.Group("/drones")
	droneMgmt.Use(authMW, RequireRoles("drone"))
	{
		droneMgmt.POST("/:id/broken", droneHandler.MarkBroken)
		droneMgmt.POST("/:id/fixed", droneHandler.MarkFixed)
	}

	adminDrones := r.Group("/admin/drones")
	adminDrones.Use(authMW, RequireRoles("admin"))
	{
		adminDrones.GET("", droneHandler.List)
		adminDrones.POST("/:id/broken", droneHandler.MarkBroken)
		adminDrones.POST("/:id/fixed", droneHandler.MarkFixed)
	}

	adminOrders := r.Group("/admin/orders")
	adminOrders.Use(authMW, RequireRoles("admin"))
	{
		adminOrders.GET("", orderHandler.AdminListOrders)
		adminOrders.PATCH("/:id", orderHandler.AdminUpdateRoute)
	}

	return r
}
