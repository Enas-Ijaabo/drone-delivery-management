package iface

import (
	"errors"
	"strconv"

	"github.com/gin-gonic/gin"
)

const (
	queryParamPage     = "page"
	queryParamPageSize = "page_size"
)

func parsePaginationParams(c *gin.Context) (int, int, error) {
	page := 0
	pageSize := 0

	if v := c.Query(queryParamPage); v != "" {
		p, err := strconv.Atoi(v)
		if err != nil {
			return 0, 0, errors.New("page must be an integer")
		}
		page = p
	}

	if v := c.Query(queryParamPageSize); v != "" {
		s, err := strconv.Atoi(v)
		if err != nil {
			return 0, 0, errors.New("page_size must be an integer")
		}
		pageSize = s
	}

	return page, pageSize, nil
}
