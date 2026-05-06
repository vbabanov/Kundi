package context_builder

import "strings"

type ChatRecord struct {
	Role string
	Text string
}

type Input struct {
	Text    string
	History []ChatRecord
}

type Context struct {
	UserQuestion          string
	RecentUserMessages    []string
	LastAssistantResponse string
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Build(input Input) Context {
	out := Context{
		UserQuestion: strings.TrimSpace(input.Text),
	}
	for i := len(input.History) - 1; i >= 0; i-- {
		record := input.History[i]
		trimmed := strings.TrimSpace(record.Text)
		if trimmed == "" {
			continue
		}
		if strings.EqualFold(record.Role, "assistant") && out.LastAssistantResponse == "" {
			out.LastAssistantResponse = trimmed
		}
		if strings.EqualFold(record.Role, "user") {
			out.RecentUserMessages = append(out.RecentUserMessages, trimmed)
			if len(out.RecentUserMessages) >= 3 {
				break
			}
		}
	}
	return out
}
