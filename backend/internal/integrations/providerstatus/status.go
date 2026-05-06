package providerstatus

import (
	"strings"

	"github.com/kundi/kundi/backend/internal/platform/config"
)

type State string

const (
	StateReady         State = "ready"
	StateMock          State = "mock"
	StateMisconfigured State = "misconfigured"
)

type Provider struct {
	Name   string `json:"name"`
	Mode   string `json:"mode"`
	State  State  `json:"state"`
	Reason string `json:"reason,omitempty"`
}

type Snapshot struct {
	LLM      Provider `json:"llm"`
	TTS      Provider `json:"tts"`
	WhatsApp Provider `json:"whatsapp"`
}

func Build(cfg config.Config) Snapshot {
	return Snapshot{
		LLM:      llmStatus(cfg),
		TTS:      ttsStatus(cfg),
		WhatsApp: whatsAppStatus(cfg),
	}
}

func (s Snapshot) HasMisconfiguredProvider() bool {
	return s.LLM.State == StateMisconfigured ||
		s.TTS.State == StateMisconfigured ||
		s.WhatsApp.State == StateMisconfigured
}

func llmStatus(cfg config.Config) Provider {
	mode := strings.ToLower(strings.TrimSpace(cfg.AI.LLMProvider))
	switch mode {
	case "", "deterministic", "mock":
		return Provider{Name: "llm", Mode: "deterministic", State: StateMock}
	case "http":
		if strings.TrimSpace(cfg.AI.LLMBaseURL) == "" {
			return Provider{Name: "llm", Mode: "http", State: StateMisconfigured, Reason: "AI_LLM_BASE_URL is required for http provider"}
		}
		if strings.TrimSpace(cfg.AI.LLMAPIKey) == "" {
			return Provider{Name: "llm", Mode: "http", State: StateMisconfigured, Reason: "AI_LLM_API_KEY is required for http provider"}
		}
		return Provider{Name: "llm", Mode: "http", State: StateReady}
	default:
		return Provider{Name: "llm", Mode: mode, State: StateMisconfigured, Reason: "unsupported provider mode"}
	}
}

func ttsStatus(cfg config.Config) Provider {
	mode := strings.ToLower(strings.TrimSpace(cfg.AI.TTSProvider))
	switch mode {
	case "", "deterministic", "mock":
		return Provider{Name: "tts", Mode: "deterministic", State: StateMock}
	case "http":
		if strings.TrimSpace(cfg.AI.TTSBaseURL) == "" {
			return Provider{Name: "tts", Mode: "http", State: StateMisconfigured, Reason: "AI_TTS_BASE_URL is required for http provider"}
		}
		if strings.TrimSpace(cfg.AI.TTSAPIKey) == "" {
			return Provider{Name: "tts", Mode: "http", State: StateMisconfigured, Reason: "AI_TTS_API_KEY is required for http provider"}
		}
		return Provider{Name: "tts", Mode: "http", State: StateReady}
	default:
		return Provider{Name: "tts", Mode: mode, State: StateMisconfigured, Reason: "unsupported provider mode"}
	}
}

func whatsAppStatus(cfg config.Config) Provider {
	mode := strings.ToLower(strings.TrimSpace(cfg.WhatsApp.Provider))
	switch mode {
	case "", "deterministic", "mock":
		return Provider{Name: "whatsapp", Mode: "deterministic", State: StateMock}
	case "http":
		if strings.TrimSpace(cfg.WhatsApp.BaseURL) == "" {
			return Provider{Name: "whatsapp", Mode: "http", State: StateMisconfigured, Reason: "WHATSAPP_BASE_URL is required for http provider"}
		}
		if strings.TrimSpace(cfg.WhatsApp.APIToken) == "" {
			return Provider{Name: "whatsapp", Mode: "http", State: StateMisconfigured, Reason: "WHATSAPP_API_TOKEN is required for http provider"}
		}
		return Provider{Name: "whatsapp", Mode: "http", State: StateReady}
	default:
		return Provider{Name: "whatsapp", Mode: mode, State: StateMisconfigured, Reason: "unsupported provider mode"}
	}
}
