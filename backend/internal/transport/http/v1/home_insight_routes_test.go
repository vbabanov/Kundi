package v1

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/app"
	"github.com/kundi/kundi/backend/internal/modules/homeinsight"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
)

type routeGradeSource struct{ grade int }

func (source routeGradeSource) GradeLevel(context.Context, uuid.UUID) (int, error) {
	return source.grade, nil
}

func TestHomeInsightRouteIsLocalizedAndGradeAware(t *testing.T) {
	service, err := homeinsight.NewService(nil, routeGradeSource{grade: 3}, homeinsight.Options{Timezone: "UTC"})
	if err != nil {
		t.Fatal(err)
	}
	studentID := uuid.New()
	tokens := platformauth.NewAccessTokenService("test-secret", time.Hour)
	token, _, err := tokens.Issue(studentID, time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	router := NewRouter(&app.Bootstrap{
		Config:       config.Config{App: config.AppConfig{Name: "test"}},
		AccessTokens: tokens,
		HomeInsight:  service,
	})

	for _, locale := range []string{"ru", "kk"} {
		response := performRequest(router, token, http.MethodGet, "/v1/home/insight?locale="+locale, "")
		if response.Code != http.StatusOK {
			t.Fatalf("locale=%s status=%d body=%s", locale, response.Code, response.Body.String())
		}
		var envelope struct {
			Data homeinsight.Insight `json:"data"`
		}
		if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
			t.Fatal(err)
		}
		if envelope.Data.Locale != locale || envelope.Data.GradeBand != homeinsight.GradeBandPrimary || envelope.Data.Text == "" {
			t.Fatalf("locale=%s insight=%+v", locale, envelope.Data)
		}
	}

	response := performRequest(router, token, http.MethodGet, "/v1/home/insight?locale=en", "")
	if response.Code != http.StatusBadRequest {
		t.Fatalf("invalid locale status=%d body=%s", response.Code, response.Body.String())
	}
}
