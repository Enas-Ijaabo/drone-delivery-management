package iface

import (
	"errors"
	"log"
	"net/http"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/Enas-Ijaabo/drone-delivery-management/internal/repo"
	"github.com/gin-gonic/gin"
)

func ErrorHandlerMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()

		if len(c.Errors) > 0 {
			for _, e := range c.Errors {
				log.Printf("error: method=%s path=%s err=%v", c.Request.Method, c.Request.URL.Path, e.Err)
			}

			err := c.Errors.Last().Err
			var repoErr *repo.RepoError
			if errors.As(err, &repoErr) {
				c.JSON(repoErr.Status(), gin.H{
					"error":   repoErr.Code,
					"message": repoErr.Message,
				})
				return
			}

			var domainErr *model.DomainError
			if errors.As(err, &domainErr) {
				response := gin.H{
					"error":   domainErr.Code,
					"message": domainErr.Message,
				}
				if len(domainErr.Details) > 0 {
					response["details"] = domainErr.Details
				}
				c.JSON(domainErr.Status(), response)
				return
			}

			c.JSON(http.StatusInternalServerError, gin.H{
				"error":   "internal_error",
				"message": "an unexpected error occurred",
			})
		}
	}
}
