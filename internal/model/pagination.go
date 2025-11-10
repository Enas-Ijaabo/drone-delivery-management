package model

const (
	DefaultPage     = 1
	DefaultPageSize = 20
	MaxPageSize     = 100
	MinPage         = 1
	MinPageSize     = 1
)

func NormalizePagination(page, pageSize int) (int, int, error) {
	if page == 0 {
		page = DefaultPage
	}
	if pageSize == 0 {
		pageSize = DefaultPageSize
	}
	if page < MinPage || pageSize < MinPageSize {
		return 0, 0, ErrInvalidPagination()
	}
	if pageSize > MaxPageSize {
		pageSize = MaxPageSize
	}

	return page, pageSize, nil
}
