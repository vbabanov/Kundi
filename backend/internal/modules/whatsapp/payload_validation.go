package whatsapp

import (
	"fmt"
	"strings"
)

const (
	maxDigestLength = 2000
)

func validateDispatchPayload(kind, message, objectKey string) error {
	switch strings.TrimSpace(kind) {
	case "homework_digest", "weekly_digest":
		trimmed := strings.TrimSpace(message)
		if trimmed == "" {
			return fmt.Errorf("digest message is required")
		}
		if len(trimmed) > maxDigestLength {
			return fmt.Errorf("digest message exceeds %d characters", maxDigestLength)
		}
		return nil
	case "homework_photo":
		if strings.TrimSpace(objectKey) == "" {
			return fmt.Errorf("object_key is required for homework photo dispatch")
		}
		return nil
	default:
		if strings.TrimSpace(message) == "" && strings.TrimSpace(objectKey) == "" {
			return fmt.Errorf("either message or object_key is required")
		}
		return nil
	}
}
