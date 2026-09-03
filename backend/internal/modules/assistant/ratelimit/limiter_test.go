package ratelimit

import (
	"testing"
	"time"
)

func TestInMemoryLimiterAllowsThenLimitsAndResets(t *testing.T) {
	now := time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC)
	limiter := NewInMemory(Config{Limit: 2, Window: time.Minute, MaxIdentities: 10, Now: func() time.Time { return now }})
	if !limiter.Allow("student-a").Allowed || !limiter.Allow("student-a").Allowed {
		t.Fatal("first two requests must be allowed")
	}
	limited := limiter.Allow("student-a")
	if limited.Allowed || limited.RetryAfter != time.Minute {
		t.Fatalf("third request must be limited for one window: %#v", limited)
	}
	if !limiter.Allow("student-b").Allowed {
		t.Fatal("a separate user must have a separate window")
	}
	now = now.Add(time.Minute)
	if !limiter.Allow("student-a").Allowed {
		t.Fatal("request must be allowed after the window resets")
	}
}

func TestInMemoryLimiterBoundedCleanup(t *testing.T) {
	now := time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC)
	limiter := NewInMemory(Config{Limit: 5, Window: time.Minute, MaxIdentities: 2, Now: func() time.Time { return now }})
	limiter.Allow("student-a")
	now = now.Add(time.Second)
	limiter.Allow("student-b")
	now = now.Add(time.Second)
	limiter.Allow("student-c")
	if limiter.Size() != 2 {
		t.Fatalf("bounded limiter must retain at most two identities, got %d", limiter.Size())
	}

	now = now.Add(2 * time.Minute)
	limiter.Allow("student-d")
	if limiter.Size() != 1 {
		t.Fatalf("expired identities must be cleaned up, got %d", limiter.Size())
	}
}
