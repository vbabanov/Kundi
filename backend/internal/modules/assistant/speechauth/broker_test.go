package speechauth

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type roundTrip func(*http.Request) (*http.Response, error)

func (f roundTrip) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func response(status int, body string) *http.Response {
	return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(body))}
}
func brokerForTest(transport roundTrip) *Broker {
	b := New(Config{Enabled: true, PrimaryKey: "fake-primary", SecondaryKey: "fake-secondary", Region: "westus"})
	b.client.Transport = transport
	return b
}
func TestKeyRotationAndSanitizedFailures(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status int
		calls  int
		code   string
	}{
		{"primary", 200, 1, ""}, {"credential401", 401, 2, ""}, {"credential403", 403, 2, ""},
		{"throttled", 429, 1, "speech_token_rate_limited"}, {"server", 500, 1, "speech_token_unavailable"},
		{"redirect", 302, 1, "speech_token_unavailable"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			b := brokerForTest(func(r *http.Request) (*http.Response, error) {
				calls++
				want := "fake-primary"
				if calls == 2 {
					want = "fake-secondary"
				}
				if r.Header.Get("Ocp-Apim-Subscription-Key") != want || r.URL.Path != "/sts/v1.0/issueToken" || r.Method != "POST" {
					t.Fatal("invalid token request")
				}
				if calls == 1 && tc.status != 200 {
					return response(tc.status, "PRIVATE-AZURE-BODY"), nil
				}
				return response(200, "fake-ephemeral-token"), nil
			})
			auth, err := b.Authorize(context.Background(), "student", "message", "kk-KZ", "hash")
			if calls != tc.calls {
				t.Fatalf("calls=%d want=%d", calls, tc.calls)
			}
			if tc.code != "" {
				if !apperrors.Is(err, tc.code) || strings.Contains(err.Error(), "PRIVATE") {
					t.Fatal("unsafe or incorrect error")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			raw, _ := json.Marshal(auth)
			if strings.Contains(string(raw), "fake-primary") || strings.Contains(string(raw), "fake-secondary") {
				t.Fatal("key escaped broker")
			}
			if auth.Voice != "kk-KZ-AigulNeural" || auth.AudioFormat != "raw-24khz-16bit-mono-pcm" {
				t.Fatal("wrong synthesis contract")
			}
			if delta := time.Until(auth.ExpiresAt); delta > TokenLifetime || delta < TokenLifetime-time.Second {
				t.Fatal("invalid expiry")
			}
		})
	}
}
func TestTimeoutNoFallback(t *testing.T) {
	calls := 0
	b := brokerForTest(func(r *http.Request) (*http.Response, error) {
		calls++
		<-r.Context().Done()
		return nil, r.Context().Err()
	})
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Millisecond)
	defer cancel()
	_, err := b.Authorize(ctx, "s", "m", "ru-RU", "")
	if calls != 1 || !apperrors.Is(err, "speech_token_timeout") {
		t.Fatal("timeout must be sanitized and not rotate")
	}
}
func TestConcurrentIssuanceIsIdempotent(t *testing.T) {
	var calls atomic.Int32
	b := brokerForTest(func(*http.Request) (*http.Response, error) {
		calls.Add(1)
		time.Sleep(time.Millisecond)
		return response(200, "token"), nil
	})
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := b.Authorize(context.Background(), "s", "m", "ru-RU", ""); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if calls.Load() != 1 {
		t.Fatal("duplicate Azure issuance")
	}
}
func TestBoundedIssuanceAndRateLimits(t *testing.T) {
	b := brokerForTest(func(*http.Request) (*http.Response, error) { return response(500, "private"), nil })
	for i := 0; i < MaxIssuancesPerMessageWindow; i++ {
		_, _ = b.Authorize(context.Background(), "s", "m", "ru", "")
	}
	if _, err := b.Authorize(context.Background(), "s", "m", "ru", ""); !apperrors.Is(err, "speech_issuance_limit") {
		t.Fatal("unbounded issuance")
	}
	for i := 0; i < RequestsPerMinute; i++ {
		if !b.AllowRequest("s") {
			t.Fatal("early rate limit")
		}
	}
	if b.AllowRequest("s") {
		t.Fatal("rate limit missing")
	}
	b.cache = make(map[string]*cached, MaxCachedMessages)
	for i := 0; i < MaxCachedMessages; i++ {
		b.cache[string(rune(i))] = &cached{until: time.Now().Add(TokenLifetime)}
	}
	if _, err := b.Authorize(context.Background(), "new", "m", "ru", ""); !apperrors.Is(err, "speech_issuance_limit") {
		t.Fatal("live entries must not be evicted")
	}
	b.now = func() time.Time { return time.Now().Add(2 * TokenLifetime) }
	_, _ = b.Authorize(context.Background(), "new", "m", "ru", "")
	if len(b.cache) != 1 || !b.AllowRequest("s") {
		t.Fatal("expired entries not pruned")
	}
}
func TestDisabledAndInvalidToken(t *testing.T) {
	b := New(Config{})
	if b.Enabled() {
		t.Fatal("default must be off")
	}
	if _, err := b.Authorize(context.Background(), "s", "m", "ru", ""); !apperrors.Is(err, "assistant_tts_disabled") {
		t.Fatal("off must not issue token")
	}
	for _, body := range []string{"", "token\nsecret", strings.Repeat("x", MaxTokenBytes+1)} {
		b = brokerForTest(func(*http.Request) (*http.Response, error) { return response(200, body), nil })
		if _, err := b.Authorize(context.Background(), "s", "m", "ru", ""); !apperrors.Is(err, "speech_token_invalid") {
			t.Fatal("invalid token accepted")
		}
	}
}

func TestEndpointAllowlistAndReturnedTokenScope(t *testing.T) {
	for _, origin := range []string{"https://example-resource.cognitiveservices.azure.com/", "https://attacker.invalid", "http://westus.api.cognitive.microsoft.com", "https://eastus.api.cognitive.microsoft.com", "https://westus.api.cognitive.microsoft.com/?key=x"} {
		calls := 0
		b := brokerForTest(func(r *http.Request) (*http.Response, error) { calls++; return response(200, "fake-token"), nil })
		b.cfg.Endpoint = origin
		auth, err := b.Authorize(context.Background(), "s", "m", "ru", "")
		if strings.Contains(origin, "example-resource") {
			if err != nil || calls != 1 || auth.Endpoint != strings.TrimRight(origin, "/") {
				t.Fatal("custom token origin was lost")
			}
		} else if !apperrors.Is(err, "speech_configuration") || calls != 0 {
			t.Fatal("unsafe token destination accepted")
		}
	}
}
