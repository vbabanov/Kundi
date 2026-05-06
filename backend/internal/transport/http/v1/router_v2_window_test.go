package v1

import (
	"net/http/httptest"
	"testing"
	"time"
)

func TestReadWindowFromRequestDefaults(t *testing.T) {
	req := httptest.NewRequest("GET", "/v2/profile", nil)
	window, err := readWindowFromRequest(req)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if window.Provider != "kundelik" {
		t.Fatalf("expected default provider kundelik, got %s", window.Provider)
	}
	if window.WindowTo.Before(window.WindowFrom) {
		t.Fatalf("invalid default window range: from=%s to=%s", window.WindowFrom, window.WindowTo)
	}
	if time.Since(window.SnapshotAt) > time.Minute {
		t.Fatalf("expected snapshot close to now, got %s", window.SnapshotAt)
	}
}

func TestReadWindowFromRequestExplicit(t *testing.T) {
	req := httptest.NewRequest("GET", "/v2/results?provider=edupage&window_from=2026-03-01&window_to=2026-03-31", nil)
	window, err := readWindowFromRequest(req)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if window.Provider != "edupage" {
		t.Fatalf("expected provider edupage, got %s", window.Provider)
	}
	if got := window.WindowFrom.Format("2006-01-02"); got != "2026-03-01" {
		t.Fatalf("unexpected window_from %s", got)
	}
	if got := window.WindowTo.Format("2006-01-02"); got != "2026-03-31" {
		t.Fatalf("unexpected window_to %s", got)
	}
}

func TestReadWindowFromRequestRejectsInvalidRange(t *testing.T) {
	req := httptest.NewRequest("GET", "/v2/results?window_from=2026-04-10&window_to=2026-03-01", nil)
	_, err := readWindowFromRequest(req)
	if err == nil {
		t.Fatalf("expected invalid range error")
	}
}

func TestReadWindowFromRequestAcceptsExplicitSnapshotAt(t *testing.T) {
	req := httptest.NewRequest(
		"GET",
		"/v2/results?provider=kundelik&window_from=2026-03-01&window_to=2026-03-31&snapshot_at=2026-04-01T09:10:11.123Z",
		nil,
	)
	window, err := readWindowFromRequest(req)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if got := window.SnapshotAt.UTC().Format(time.RFC3339); got != "2026-04-01T09:10:11Z" {
		t.Fatalf("unexpected snapshot_at %s", got)
	}
}

func TestReadWindowFromRequestRejectsInvalidSnapshotAt(t *testing.T) {
	req := httptest.NewRequest(
		"GET",
		"/v2/results?snapshot_at=2026-04-01",
		nil,
	)
	_, err := readWindowFromRequest(req)
	if err == nil {
		t.Fatalf("expected invalid snapshot_at error")
	}
}

func TestReadWindowFromRequestUsesSameExplicitSnapshotAcrossEndpoints(t *testing.T) {
	const snapshot = "2026-04-01T09:10:11Z"
	profileReq := httptest.NewRequest(
		"GET",
		"/v2/profile?window_from=2026-03-01&window_to=2026-03-31&snapshot_at="+snapshot,
		nil,
	)
	resultsReq := httptest.NewRequest(
		"GET",
		"/v2/results?window_from=2026-03-01&window_to=2026-03-31&snapshot_at="+snapshot,
		nil,
	)
	overviewReq := httptest.NewRequest(
		"GET",
		"/v2/academic/overview?window_from=2026-03-01&window_to=2026-03-31&snapshot_at="+snapshot,
		nil,
	)

	profileWindow, err := readWindowFromRequest(profileReq)
	if err != nil {
		t.Fatalf("profile window parse failed: %v", err)
	}
	resultsWindow, err := readWindowFromRequest(resultsReq)
	if err != nil {
		t.Fatalf("results window parse failed: %v", err)
	}
	overviewWindow, err := readWindowFromRequest(overviewReq)
	if err != nil {
		t.Fatalf("overview window parse failed: %v", err)
	}

	want := "2026-04-01T09:10:11Z"
	if got := profileWindow.SnapshotAt.UTC().Format(time.RFC3339); got != want {
		t.Fatalf("profile snapshot mismatch: got %s want %s", got, want)
	}
	if got := resultsWindow.SnapshotAt.UTC().Format(time.RFC3339); got != want {
		t.Fatalf("results snapshot mismatch: got %s want %s", got, want)
	}
	if got := overviewWindow.SnapshotAt.UTC().Format(time.RFC3339); got != want {
		t.Fatalf("overview snapshot mismatch: got %s want %s", got, want)
	}
}
