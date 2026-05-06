package jobs

import (
	"testing"
	"time"
)

func TestRetryBackoffBounds(t *testing.T) {
	tests := []struct {
		attempt int
		want    time.Duration
	}{
		{attempt: 1, want: 15 * time.Second},
		{attempt: 2, want: 60 * time.Second},
		{attempt: 3, want: 135 * time.Second},
		{attempt: 10, want: 300 * time.Second},
	}
	for _, tc := range tests {
		got := retryBackoff(tc.attempt)
		if got != tc.want {
			t.Fatalf("attempt=%d: want=%s got=%s", tc.attempt, tc.want, got)
		}
	}
}
