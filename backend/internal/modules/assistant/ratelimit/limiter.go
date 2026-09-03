package ratelimit

import (
	"sync"
	"time"
)

const (
	DefaultLimit         = 20
	DefaultWindow        = time.Minute
	DefaultMaxIdentities = 10_000
)

type Decision struct {
	Allowed    bool
	RetryAfter time.Duration
}

type Limiter interface {
	Allow(identity string) Decision
}

type Config struct {
	Limit         int
	Window        time.Duration
	MaxIdentities int
	Now           func() time.Time
}

func DefaultConfig() Config {
	return Config{
		Limit:         DefaultLimit,
		Window:        DefaultWindow,
		MaxIdentities: DefaultMaxIdentities,
		Now:           time.Now,
	}
}

type entry struct {
	windowStarted time.Time
	lastSeen      time.Time
	count         int
}

type InMemory struct {
	mu            sync.Mutex
	limit         int
	window        time.Duration
	maxIdentities int
	now           func() time.Time
	entries       map[string]entry
}

func NewInMemory(cfg Config) *InMemory {
	defaults := DefaultConfig()
	if cfg.Limit <= 0 {
		cfg.Limit = defaults.Limit
	}
	if cfg.Window <= 0 {
		cfg.Window = defaults.Window
	}
	if cfg.MaxIdentities <= 0 {
		cfg.MaxIdentities = defaults.MaxIdentities
	}
	if cfg.Now == nil {
		cfg.Now = defaults.Now
	}
	return &InMemory{
		limit:         cfg.Limit,
		window:        cfg.Window,
		maxIdentities: cfg.MaxIdentities,
		now:           cfg.Now,
		entries:       make(map[string]entry),
	}
}

func (l *InMemory) Allow(identity string) Decision {
	now := l.now()
	l.mu.Lock()
	defer l.mu.Unlock()

	current, exists := l.entries[identity]
	if exists && now.Sub(current.windowStarted) >= l.window {
		current = entry{}
		exists = false
	}
	if !exists {
		l.makeRoom(now, identity)
		l.entries[identity] = entry{windowStarted: now, lastSeen: now, count: 1}
		return Decision{Allowed: true}
	}

	current.lastSeen = now
	if current.count >= l.limit {
		l.entries[identity] = current
		retryAfter := l.window - now.Sub(current.windowStarted)
		if retryAfter < 0 {
			retryAfter = 0
		}
		return Decision{Allowed: false, RetryAfter: retryAfter}
	}
	current.count++
	l.entries[identity] = current
	return Decision{Allowed: true}
}

func (l *InMemory) Size() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.entries)
}

func (l *InMemory) makeRoom(now time.Time, incomingIdentity string) {
	if _, exists := l.entries[incomingIdentity]; exists {
		return
	}
	for identity, candidate := range l.entries {
		if now.Sub(candidate.windowStarted) >= l.window {
			delete(l.entries, identity)
		}
	}
	if len(l.entries) < l.maxIdentities {
		return
	}
	var oldestIdentity string
	var oldestTime time.Time
	for identity, candidate := range l.entries {
		if oldestIdentity == "" || candidate.lastSeen.Before(oldestTime) {
			oldestIdentity = identity
			oldestTime = candidate.lastSeen
		}
	}
	if oldestIdentity != "" {
		delete(l.entries, oldestIdentity)
	}
}
