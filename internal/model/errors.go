package model

import "fmt"

type DomainError struct {
	Code       string
	Message    string
	Details    map[string]interface{}
	Cause      error
	StatusCode int
}

func (e *DomainError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Cause)
	}
	return e.Message
}

func (e *DomainError) Unwrap() error {
	return e.Cause
}

func (e *DomainError) Status() int {
	if e.StatusCode != 0 {
		return e.StatusCode
	}
	return 400
}

func NewDomainError(code, message string) *DomainError {
	return &DomainError{
		Code:    code,
		Message: message,
		Details: make(map[string]interface{}),
	}
}

func NewDomainErrorWithDetails(code, message string, details map[string]interface{}) *DomainError {
	return &DomainError{
		Code:    code,
		Message: message,
		Details: details,
	}
}

func NewDomainErrorWithCause(code, message string, cause error) *DomainError {
	return &DomainError{
		Code:    code,
		Message: message,
		Details: make(map[string]interface{}),
		Cause:   cause,
	}
}

const (
	ErrCodeOrderStatusTransitionNotAllowed = "order_status_transition_not_allowed"
	ErrCodeDroneStatusTransitionNotAllowed = "drone_status_transition_not_allowed"
	ErrCodeOrderNotOwned                   = "order_not_owned"
	ErrCodeOrderNotAssignedToDrone         = "order_not_assigned_to_drone"
)

func ErrOrderTransitionNotAllowed(from, to string) *DomainError {
	return &DomainError{
		Code:    ErrCodeOrderStatusTransitionNotAllowed,
		Message: fmt.Sprintf("transition from %s to %s is not allowed", from, to),
		Details: map[string]interface{}{
			"from": from,
			"to":   to,
		},
		StatusCode: 409,
	}
}

func ErrDroneTransitionNotAllowed(from, to string) *DomainError {
	return NewDomainErrorWithDetails(
		ErrCodeDroneStatusTransitionNotAllowed,
		fmt.Sprintf("transition from %s to %s is not allowed", from, to),
		map[string]interface{}{
			"from": from,
			"to":   to,
		},
	)
}

func ErrOrderNotOwned() *DomainError {
	return &DomainError{
		Code:       ErrCodeOrderNotOwned,
		Message:    "order does not belong to user",
		Details:    make(map[string]interface{}),
		StatusCode: 403,
	}
}

func ErrOrderNotAssignedToDrone() *DomainError {
	return &DomainError{
		Code:       ErrCodeOrderNotAssignedToDrone,
		Message:    "order is not assigned to this drone",
		Details:    make(map[string]interface{}),
		StatusCode: 404,
	}
}
