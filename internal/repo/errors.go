package repo

import "fmt"

type RepoError struct {
	Code       string
	Message    string
	StatusCode int
	Cause      error
}

func (e *RepoError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Cause)
	}
	return e.Message
}

func (e *RepoError) Unwrap() error {
	return e.Cause
}

func (e *RepoError) Status() int {
	return e.StatusCode
}

func NewRepoError(code, message string, statusCode int) *RepoError {
	return &RepoError{
		Code:       code,
		Message:    message,
		StatusCode: statusCode,
	}
}

func NewRepoErrorWithCause(code, message string, statusCode int, cause error) *RepoError {
	return &RepoError{
		Code:       code,
		Message:    message,
		StatusCode: statusCode,
		Cause:      cause,
	}
}

const (
	ErrCodeUserNotFound      = "user_not_found"
	ErrCodeOrderNotFound     = "order_not_found"
	ErrCodeInvalidForeignKey = "invalid_foreign_key"
	ErrCodeInvalidEnduserID  = "invalid_enduser_id"
)

func ErrUserNotFound() *RepoError {
	return NewRepoError(ErrCodeUserNotFound, "user not found", 404)
}

func ErrOrderNotFound() *RepoError {
	return NewRepoError(ErrCodeOrderNotFound, "order not found", 404)
}

func ErrInvalidEnduserID() *RepoError {
	return NewRepoError(ErrCodeInvalidEnduserID, "invalid enduser id", 400)
}
