package safety

import (
	"fmt"
	"net/netip"
	"net/url"
	"strings"
)

type AudioURLValidator struct {
	trustedHosts map[string]struct{}
}

func NewAudioURLValidator(trustedHosts []string) *AudioURLValidator {
	allowed := make(map[string]struct{}, len(trustedHosts))
	for _, host := range trustedHosts {
		host = canonicalHost(host)
		if host != "" {
			allowed[host] = struct{}{}
		}
	}
	return &AudioURLValidator{trustedHosts: allowed}
}

func (v *AudioURLValidator) Validate(rawURL string) (string, error) {
	trimmed := strings.TrimSpace(rawURL)
	parsed, err := url.Parse(trimmed)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return "", fmt.Errorf("audio URL is malformed")
	}
	if !strings.EqualFold(parsed.Scheme, "https") {
		return "", fmt.Errorf("audio URL must use HTTPS")
	}
	if parsed.User != nil {
		return "", fmt.Errorf("audio URL must not include user info")
	}
	host := canonicalHost(parsed.Hostname())
	if host == "" || isLocalHostname(host) || isUnsafeIPAddress(host) {
		return "", fmt.Errorf("audio URL host is not public")
	}
	if _, ok := v.trustedHosts[host]; !ok {
		return "", fmt.Errorf("audio URL host is not trusted")
	}
	return parsed.String(), nil
}

func canonicalHost(host string) string {
	return strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
}

func isLocalHostname(host string) bool {
	if host == "localhost" || strings.HasSuffix(host, ".localhost") {
		return true
	}
	for _, suffix := range []string{".local", ".internal", ".lan", ".home", ".home.arpa"} {
		if strings.HasSuffix(host, suffix) {
			return true
		}
	}
	return false
}

func isUnsafeIPAddress(host string) bool {
	addr, err := netip.ParseAddr(host)
	if err != nil {
		return false
	}
	return addr.IsLoopback() || addr.IsPrivate() || addr.IsLinkLocalUnicast() || addr.IsLinkLocalMulticast() || addr.IsUnspecified()
}
