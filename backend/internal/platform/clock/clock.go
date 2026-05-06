package clock

import "time"

// Clock allows deterministic testing for time-sensitive business logic.
type Clock interface {
	Now() time.Time
}

// SystemClock is the production clock implementation.
type SystemClock struct{}

func (SystemClock) Now() time.Time {
	return time.Now().UTC()
}
