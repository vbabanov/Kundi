package v1

import (
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestDecodeSendHomeworkDigestRequestJSON(t *testing.T) {
	req := httptest.NewRequest(
		"POST",
		"/v1/whatsapp/send-homework",
		strings.NewReader(`{"date":"2026-04-27","mode":"homework"}`),
	)
	decoded, err := decodeSendHomeworkDigestRequest(req)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if decoded.Date != "2026-04-27" {
		t.Fatalf("unexpected date: %s", decoded.Date)
	}
	if decoded.Mode != "homework" {
		t.Fatalf("unexpected mode: %s", decoded.Mode)
	}
}

func TestDecodeSendHomeworkDigestRequestFormFallback(t *testing.T) {
	req := httptest.NewRequest(
		"POST",
		"/v1/whatsapp/send-homework",
		strings.NewReader("date=2026-04-27&mode=topic"),
	)
	decoded, err := decodeSendHomeworkDigestRequest(req)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if decoded.Date != "2026-04-27" {
		t.Fatalf("unexpected date: %s", decoded.Date)
	}
	if decoded.Mode != "topic" {
		t.Fatalf("unexpected mode: %s", decoded.Mode)
	}
}

func TestDecodeSendHomeworkDigestRequestEmptyBody(t *testing.T) {
	req := httptest.NewRequest(
		"POST",
		"/v1/whatsapp/send-homework",
		strings.NewReader(""),
	)
	decoded, err := decodeSendHomeworkDigestRequest(req)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if decoded.Date != "" || decoded.Mode != "" {
		t.Fatalf("expected empty request, got date=%q mode=%q", decoded.Date, decoded.Mode)
	}
}

func TestWriteHomeworkPhotoTempFile(t *testing.T) {
	path, err := writeHomeworkPhotoTempFile("homework.jpg", []byte("abc"))
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	defer func() {
		_ = os.Remove(path)
	}()
	stat, err := os.Stat(path)
	if err != nil {
		t.Fatalf("expected temp file to exist: %v", err)
	}
	if stat.Size() != 3 {
		t.Fatalf("unexpected file size: %d", stat.Size())
	}
}
