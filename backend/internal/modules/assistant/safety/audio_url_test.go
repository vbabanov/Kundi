package safety

import "testing"

func TestAudioURLValidator(t *testing.T) {
	validator := NewAudioURLValidator([]string{"media.example.com", "8.8.8.8"})
	tests := []struct {
		name    string
		raw     string
		allowed bool
	}{
		{name: "trusted HTTPS", raw: "https://media.example.com/audio/one.mp3", allowed: true},
		{name: "HTTP", raw: "http://media.example.com/audio/one.mp3"},
		{name: "localhost", raw: "https://localhost/audio/one.mp3"},
		{name: "loopback v4", raw: "https://127.0.0.1/audio/one.mp3"},
		{name: "loopback v6", raw: "https://[::1]/audio/one.mp3"},
		{name: "private v4", raw: "https://10.10.1.4/audio/one.mp3"},
		{name: "link local", raw: "https://169.254.10.2/audio/one.mp3"},
		{name: "special local host", raw: "https://cdn.kundi.local/audio/one.mp3"},
		{name: "untrusted", raw: "https://other.example.com/audio/one.mp3"},
		{name: "malformed", raw: "://not-a-url"},
		{name: "file scheme", raw: "file:///tmp/audio.mp3"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := validator.Validate(test.raw)
			if test.allowed && (err != nil || got != test.raw) {
				t.Fatalf("expected URL to be accepted, got %q err=%v", got, err)
			}
			if !test.allowed && err == nil {
				t.Fatalf("expected URL to be rejected, got %q", got)
			}
		})
	}
}
