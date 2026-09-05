package providerstatus

import (
	"net/url"
	"regexp"
	"strings"

	"github.com/kundi/kundi/backend/internal/platform/config"
)

var (
	azureSpeechRegionPattern   = regexp.MustCompile(`^[a-z0-9]+$`)
	azureSpeechResourcePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*\.cognitiveservices\.azure\.com$`)
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
	if cfg.AI.AssistantEnabled {
		if strings.TrimSpace(cfg.AI.AlemBaseURL) == "" {
			return Provider{Name: "llm", Mode: "alem", State: StateMisconfigured, Reason: "ALEM_BASE_URL is required"}
		}
		if firstConfigured(cfg.AI.AlemPrimaryAPIKey, cfg.AI.AlemAPIKey) == "" {
			return Provider{Name: "llm", Mode: "alem", State: StateMisconfigured, Reason: "ALEM_PRIMARY_API_KEY or ALEM_API_KEY is required"}
		}
		if strings.TrimSpace(cfg.AI.AlemPrimaryModel) == "" {
			return Provider{Name: "llm", Mode: "alem", State: StateMisconfigured, Reason: "ALEM_PRIMARY_MODEL is required"}
		}
		if strings.TrimSpace(cfg.AI.AlemFallbackModel) != "" && firstConfigured(cfg.AI.AlemFallbackAPIKey, cfg.AI.AlemAPIKey) == "" {
			return Provider{Name: "llm", Mode: "alem", State: StateMisconfigured, Reason: "ALEM_FALLBACK_API_KEY or ALEM_API_KEY is required when ALEM_FALLBACK_MODEL is configured"}
		}
		return Provider{Name: "llm", Mode: "alem", State: StateReady}
	}
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

func firstConfigured(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func ttsStatus(cfg config.Config) Provider {
	if cfg.AI.KundiTTSEnabled {
		return azureSpeechStatus(cfg)
	}

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

func azureSpeechStatus(cfg config.Config) Provider {
	const mode = "azure-speech"
	if !cfg.AI.AssistantEnabled {
		return Provider{Name: "tts", Mode: mode, State: StateMisconfigured, Reason: "KUNDI_ASSISTANT_ENABLED is required when KUNDI_TTS_ENABLED=true"}
	}
	if !cfg.AI.VoiceInputEnabled {
		return Provider{Name: "tts", Mode: mode, State: StateMisconfigured, Reason: "KUNDI_VOICE_INPUT_ENABLED is required when KUNDI_TTS_ENABLED=true"}
	}
	if strings.TrimSpace(cfg.AI.AzureSpeechKeyPrimary) == "" {
		return Provider{Name: "tts", Mode: mode, State: StateMisconfigured, Reason: "AZURE_SPEECH_KEY_PRIMARY is required"}
	}
	region := strings.TrimSpace(cfg.AI.AzureSpeechRegion)
	if region != cfg.AI.AzureSpeechRegion || !azureSpeechRegionPattern.MatchString(region) {
		return Provider{Name: "tts", Mode: mode, State: StateMisconfigured, Reason: "AZURE_SPEECH_REGION must be a valid Azure region"}
	}
	if cfg.AI.AzureSpeechVoiceRU != "ru-RU-SvetlanaNeural" {
		return Provider{Name: "tts", Mode: mode, State: StateMisconfigured, Reason: "AZURE_SPEECH_VOICE_RU must be ru-RU-SvetlanaNeural"}
	}
	if cfg.AI.AzureSpeechVoiceKK != "kk-KZ-AigulNeural" {
		return Provider{Name: "tts", Mode: mode, State: StateMisconfigured, Reason: "AZURE_SPEECH_VOICE_KK must be kk-KZ-AigulNeural"}
	}
	if endpoint := cfg.AI.AzureSpeechEndpoint; endpoint != "" && (strings.TrimSpace(endpoint) != endpoint || !validAzureSpeechEndpoint(endpoint, region)) {
		return Provider{Name: "tts", Mode: mode, State: StateMisconfigured, Reason: "AZURE_SPEECH_ENDPOINT must be empty or a valid Azure HTTPS endpoint"}
	}
	return Provider{Name: "tts", Mode: mode, State: StateReady}
}

func validAzureSpeechEndpoint(endpoint, region string) bool {
	u, err := url.Parse(endpoint)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.Port() != "" ||
		u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return false
	}
	host := strings.ToLower(u.Hostname())
	return host == region+".api.cognitive.microsoft.com" || azureSpeechResourcePattern.MatchString(host)
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
