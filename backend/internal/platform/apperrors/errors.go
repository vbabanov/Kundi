package apperrors

import (
	"errors"
	"fmt"
	"net/http"
)

// Error is a structured runtime error returned by handlers and services.
type Error struct {
	Code       string         `json:"code"`
	Message    string         `json:"message"`
	StatusCode int            `json:"-"`
	Details    map[string]any `json:"details,omitempty"`
	Err        error          `json:"-"`
}

func (e *Error) Error() string {
	if e == nil {
		return ""
	}
	if e.Err == nil {
		return e.Message
	}
	return fmt.Sprintf("%s: %v", e.Message, e.Err)
}

func (e *Error) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.Err
}

func New(status int, code, message string, err error) *Error {
	return &Error{
		Code:       code,
		Message:    message,
		StatusCode: status,
		Err:        err,
	}
}

func BadRequest(code, message string) *Error {
	return New(http.StatusBadRequest, code, message, nil)
}

func Unauthorized(code, message string) *Error {
	return New(http.StatusUnauthorized, code, message, nil)
}

func Forbidden(code, message string) *Error {
	return New(http.StatusForbidden, code, message, nil)
}

func NotFound(code, message string) *Error {
	return New(http.StatusNotFound, code, message, nil)
}

func Conflict(code, message string) *Error {
	return New(http.StatusConflict, code, message, nil)
}

func Internal(code, message string, err error) *Error {
	return New(http.StatusInternalServerError, code, message, err)
}

func Is(err error, code string) bool {
	var appErr *Error
	if !errors.As(err, &appErr) {
		return false
	}
	return appErr.Code == code
}

func StatusCode(err error) int {
	var appErr *Error
	if errors.As(err, &appErr) && appErr.StatusCode != 0 {
		return appErr.StatusCode
	}
	return http.StatusInternalServerError
}
