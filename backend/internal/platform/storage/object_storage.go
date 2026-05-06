package storage

import "context"

// ObjectStorage abstracts media persistence (photo/audio assets).
type ObjectStorage interface {
	Put(ctx context.Context, key string, contentType string, body []byte) (publicURL string, err error)
}

type NoopObjectStorage struct{}

func (NoopObjectStorage) Put(_ context.Context, _ string, _ string, _ []byte) (string, error) {
	return "", nil
}
