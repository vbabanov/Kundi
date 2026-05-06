package whatsapp

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const mediaObjectKeyPrefix = "file://"

func mediaObjectPath(objectKey string) (string, bool) {
	trimmed := strings.TrimSpace(objectKey)
	if !strings.HasPrefix(trimmed, mediaObjectKeyPrefix) {
		return "", false
	}
	path := strings.TrimSpace(strings.TrimPrefix(trimmed, mediaObjectKeyPrefix))
	if path == "" {
		return "", false
	}
	return path, true
}

func removeMediaObject(objectKey string) error {
	path, ok := mediaObjectPath(objectKey)
	if !ok {
		return nil
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove media object %s: %w", filepath.Base(path), err)
	}
	return nil
}
