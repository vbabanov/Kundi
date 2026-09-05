// Package speechauth issues ephemeral Azure credentials. It never synthesizes,
// logs response bodies, or persists credentials. Resource tokens are NOT text-scoped.
package speechauth

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

const (
	TokenLifetime      = 10 * time.Minute
	ClientSafetyMargin = time.Minute
	IssueTimeout       = 5 * time.Second
	MaxTokenBytes      = 16 * 1024
	MaxCachedMessages  = 2048
	MaxRateIdentities  = 10000
	RequestsPerMinute  = 10
	// Includes failed issuance attempts; retries cannot create unlimited tokens.
	MaxIssuancesPerMessageWindow = 2
)

type Config struct {
	Enabled                                                      bool
	PrimaryKey, SecondaryKey, Region, Endpoint, VoiceRU, VoiceKK string
}
type Authorization struct {
	Token         string    `json:"authorization_token"`
	ExpiresAt     time.Time `json:"expires_at"`
	Region        string    `json:"region"`
	Endpoint      string    `json:"endpoint"`
	Locale        string    `json:"locale"`
	Voice         string    `json:"voice"`
	MessageID     string    `json:"message_id"`
	ContentSHA256 string    `json:"message_content_sha256"`
	AudioFormat   string    `json:"audio_format"`
	SampleRate    int       `json:"sample_rate_hz"`
	Channels      int       `json:"channels"`
	BitsPerSample int       `json:"bits_per_sample"`
}
type cached struct {
	until    time.Time
	attempts int
	token    string
	expires  time.Time
	pending  chan struct{}
}
type rateEntry struct {
	until time.Time
	count int
}
type Broker struct {
	cfg    Config
	client *http.Client
	now    func() time.Time
	mu     sync.Mutex
	cache  map[string]*cached
	rates  map[string]rateEntry
	slots  chan struct{}
}

func New(cfg Config) *Broker {
	return &Broker{cfg: cfg, client: &http.Client{Timeout: IssueTimeout,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
		now: time.Now, cache: map[string]*cached{}, rates: map[string]rateEntry{}, slots: make(chan struct{}, 8)}
}
func (b *Broker) Enabled() bool { return b != nil && b.cfg.Enabled }

func failure(status int, code string) error {
	return apperrors.New(status, code, "speech authorization unavailable", nil)
}

// AllowRequest is independent of Assistant's LLM limiter, including cached hits.
// Capacity exhaustion fails closed; active identities are never evicted.
func (b *Broker) AllowRequest(studentID string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := b.now()
	for id, r := range b.rates {
		if !now.Before(r.until) {
			delete(b.rates, id)
		}
	}
	r, ok := b.rates[studentID]
	if !ok {
		if len(b.rates) >= MaxRateIdentities {
			return false
		}
		r.until = now.Add(time.Minute)
	}
	if r.count >= RequestsPerMinute {
		return false
	}
	r.count++
	b.rates[studentID] = r
	return true
}

func (b *Broker) Authorize(ctx context.Context, studentID, messageID, locale, hash string) (Authorization, error) {
	if !b.Enabled() {
		return Authorization{}, failure(404, "assistant_tts_disabled")
	}
	cfg := b.cfg
	if !regexp.MustCompile(`^[a-z0-9]+$`).MatchString(cfg.Region) {
		return Authorization{}, failure(503, "speech_configuration")
	}
	// Restrict the configured token origin and never follow redirects carrying keys.
	endpoint := "https://" + cfg.Region + ".api.cognitive.microsoft.com"
	if cfg.Endpoint != "" {
		u, err := url.Parse(cfg.Endpoint)
		if err != nil || u.Scheme != "https" ||
			(u.Host != cfg.Region+".api.cognitive.microsoft.com" && !regexp.MustCompile(`^[a-z0-9][a-z0-9-]*\.cognitiveservices\.azure\.com$`).MatchString(u.Host)) ||
			u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
			return Authorization{}, failure(503, "speech_configuration")
		}
		endpoint = strings.TrimRight(cfg.Endpoint, "/")
	}
	if cfg.PrimaryKey == "" {
		return Authorization{}, failure(503, "speech_configuration")
	}
	voice := cfg.VoiceRU
	normalized := "ru-RU"
	if strings.HasPrefix(strings.ToLower(locale), "kk") {
		voice = cfg.VoiceKK
		normalized = "kk-KZ"
	}
	if voice == "" {
		if normalized == "kk-KZ" {
			voice = "kk-KZ-AigulNeural"
		} else {
			voice = "ru-RU-SvetlanaNeural"
		}
	}
	if (normalized == "kk-KZ" && voice != "kk-KZ-AigulNeural") || (normalized == "ru-RU" && voice != "ru-RU-SvetlanaNeural") {
		return Authorization{}, failure(503, "speech_configuration")
	}
	key := studentID + ":" + messageID
	token, expires, err := b.token(ctx, key, endpoint)
	if err != nil {
		return Authorization{}, err
	}
	return Authorization{Token: token, ExpiresAt: expires, Region: cfg.Region, Endpoint: endpoint,
		Locale: normalized, Voice: voice, MessageID: messageID, ContentSHA256: hash,
		AudioFormat: "raw-24khz-16bit-mono-pcm", SampleRate: 24000, Channels: 1, BitsPerSample: 16}, nil
}

func (b *Broker) token(ctx context.Context, key, endpoint string) (string, time.Time, error) {
	for {
		b.mu.Lock()
		now := b.now()
		for id, c := range b.cache {
			if c.pending == nil && !now.Before(c.until) {
				delete(b.cache, id)
			}
		}
		c := b.cache[key]
		if c == nil {
			if len(b.cache) >= MaxCachedMessages {
				b.mu.Unlock()
				return "", time.Time{}, failure(429, "speech_issuance_limit")
			}
			c = &cached{until: now.Add(TokenLifetime)}
			b.cache[key] = c
		}
		if c.pending != nil {
			done := c.pending
			b.mu.Unlock()
			select {
			case <-done:
				continue
			case <-ctx.Done():
				return "", time.Time{}, failure(504, "speech_token_timeout")
			}
		}
		if c.token != "" && now.Add(ClientSafetyMargin).Before(c.expires) {
			token, expiry := c.token, c.expires
			b.mu.Unlock()
			return token, expiry, nil
		}
		if c.attempts >= MaxIssuancesPerMessageWindow {
			b.mu.Unlock()
			return "", time.Time{}, failure(429, "speech_issuance_limit")
		}
		select {
		case b.slots <- struct{}{}:
		default:
			b.mu.Unlock()
			return "", time.Time{}, failure(429, "speech_busy")
		}
		c.attempts++
		c.pending = make(chan struct{})
		b.mu.Unlock()
		requestCtx, cancel := context.WithTimeout(ctx, IssueTimeout)
		token, status, err := b.issue(requestCtx, endpoint, b.cfg.PrimaryKey)
		if (status == 401 || status == 403) && b.cfg.SecondaryKey != "" && requestCtx.Err() == nil {
			token, _, err = b.issue(requestCtx, endpoint, b.cfg.SecondaryKey)
		}
		cancel()
		<-b.slots
		b.mu.Lock()
		if err == nil {
			c.token = token
			c.expires = now.Add(TokenLifetime)
		}
		expires := c.expires
		close(c.pending)
		c.pending = nil
		b.mu.Unlock()
		return token, expires, err
	}
}

func (b *Broker) issue(ctx context.Context, endpoint, key string) (string, int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint+"/sts/v1.0/issueToken", nil)
	if err != nil {
		return "", 0, failure(503, "speech_configuration")
	}
	req.Header.Set("Ocp-Apim-Subscription-Key", key)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := b.client.Do(req)
	if err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return "", 0, failure(504, "speech_token_timeout")
		}
		return "", 0, failure(503, "speech_token_unavailable")
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		code, status := "speech_token_unavailable", 503
		if res.StatusCode == 401 || res.StatusCode == 403 {
			code = "speech_credentials"
		}
		if res.StatusCode == 429 {
			code = "speech_token_rate_limited"
			status = 429
		}
		// Do not read, wrap, or log Azure's error body.
		return "", res.StatusCode, failure(status, code)
	}
	body, err := io.ReadAll(io.LimitReader(res.Body, MaxTokenBytes+1))
	if err != nil || len(body) == 0 || len(body) > MaxTokenBytes {
		return "", 200, failure(503, "speech_token_invalid")
	}
	token := strings.TrimSpace(string(body))
	if token == "" || strings.ContainsAny(token, "\r\n \t") {
		return "", 200, failure(503, "speech_token_invalid")
	}
	return token, 200, nil
}
