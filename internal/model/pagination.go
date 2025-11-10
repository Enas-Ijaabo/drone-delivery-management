package model

const (
	defaultPage     = 1
	defaultPageSize = 20
	maxPageSize     = 100
)

type Pagination struct {
	Page     int
	PageSize int
	Offset   int
}

func NormalizePagination(page, pageSize int) (Pagination, error) {
	if page <= 0 {
		page = defaultPage
	}
	if pageSize <= 0 {
		pageSize = defaultPageSize
	}
	if page < 1 || pageSize < 1 {
		return Pagination{}, ErrInvalidPagination()
	}
	if pageSize > maxPageSize {
		pageSize = maxPageSize
	}
	return Pagination{
		Page:     page,
		PageSize: pageSize,
		Offset:   (page - 1) * pageSize,
	}, nil
}

func (p Pagination) HasNext(resultCount int) bool {
	return resultCount == p.PageSize
}
