package auth

import (
	"context"
	"net/http"
	"strings"
)

type ContextKey string

const StudentIDContextKey ContextKey = "student_id"

func StudentIDFromContext(ctx context.Context) (string, bool) {
	raw := ctx.Value(StudentIDContextKey)
	studentID, ok := raw.(string)
	return studentID, ok && studentID != ""
}

func Middleware(tokens *AccessTokenService, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
		if !strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
			http.Error(w, "missing bearer token", http.StatusUnauthorized)
			return
		}
		token := strings.TrimSpace(authHeader[len("Bearer "):])
		claims, err := tokens.Parse(token)
		if err != nil {
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return
		}
		ctx := context.WithValue(r.Context(), StudentIDContextKey, claims.StudentID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
