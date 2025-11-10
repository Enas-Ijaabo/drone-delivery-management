package iface

import "github.com/gin-gonic/gin"

// HealthHandler godoc
// @Summary Health check
// @Description Check if the API is running
// @Tags health
// @Produce plain
// @Success 200 {string} string "OK"
// @Router /health [get]
func HealthHandler(c *gin.Context) {
	c.String(200, "OK")
}
