package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
)

// FieldCipher encrypts sensitive columns before DB persistence.
type FieldCipher struct {
	aead cipher.AEAD
}

func NewFieldCipher(key string) (*FieldCipher, error) {
	block, err := aes.NewCipher([]byte(key))
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &FieldCipher{aead: aead}, nil
}

func (c *FieldCipher) Encrypt(plain string) ([]byte, error) {
	nonce := make([]byte, c.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}
	sealed := c.aead.Seal(nonce, nonce, []byte(plain), nil)
	out := make([]byte, base64.StdEncoding.EncodedLen(len(sealed)))
	base64.StdEncoding.Encode(out, sealed)
	return out, nil
}

func (c *FieldCipher) Decrypt(ciphertext []byte) (string, error) {
	raw := make([]byte, base64.StdEncoding.DecodedLen(len(ciphertext)))
	n, err := base64.StdEncoding.Decode(raw, ciphertext)
	if err != nil {
		return "", fmt.Errorf("decode base64: %w", err)
	}
	raw = raw[:n]
	if len(raw) < c.aead.NonceSize() {
		return "", fmt.Errorf("ciphertext is too short")
	}
	nonce, data := raw[:c.aead.NonceSize()], raw[c.aead.NonceSize():]
	plain, err := c.aead.Open(nil, nonce, data, nil)
	if err != nil {
		return "", err
	}
	return string(plain), nil
}
