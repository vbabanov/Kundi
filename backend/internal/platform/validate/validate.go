package validate

import (
	"regexp"
	"strings"
)

var idempotencyKeyPattern = regexp.MustCompile(`^[A-Za-z0-9._:-]{8,128}$`)

func Required(value string) bool {
	return strings.TrimSpace(value) != ""
}

func MaxLen(value string, max int) bool {
	return len(value) <= max
}

func IdempotencyKey(value string) bool {
	return idempotencyKeyPattern.MatchString(strings.TrimSpace(value))
}

func Source(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "kundelik", "dnevnikru", "edupage":
		return true
	default:
		return false
	}
}
