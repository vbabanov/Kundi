package httpx

import (
	"encoding/json"
	"net/http"

	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type Envelope struct {
	Data  any    `json:"data,omitempty"`
	Error *Error `json:"error,omitempty"`
}

type Error struct {
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

func JSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(Envelope{Data: data})
}

func JSONError(w http.ResponseWriter, err error) {
	status := apperrors.StatusCode(err)
	appErr, ok := err.(*apperrors.Error)
	if !ok {
		appErr = apperrors.Internal("internal_error", "internal server error", err)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(Envelope{
		Error: &Error{Code: appErr.Code, Message: appErr.Message, Details: appErr.Details},
	})
}
