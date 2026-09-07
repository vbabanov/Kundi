package tutoring

import (
	"fmt"
	"strings"
	"testing"
)

func TestCommunicationProfilesCoverFiveAgeBandsAndChannels(t *testing.T) {
	tests := []struct {
		grade     int
		band      string
		rolePart  string
		shapePart string
		voiceMax  int
	}{
		{1, "1-2", "patient learning companion", "exactly one idea", 240},
		{3, "3-4", "warm learning guide", "one concrete example", 380},
		{6, "5-7", "friendly coach", "useful example or hint", 520},
		{8, "8-9", "respectful coach", "justify the important steps", 650},
		{11, "10-11", "mentor", "argument quality", 800},
	}
	service := NewService()
	for _, test := range tests {
		for _, channel := range []string{"text", "voice"} {
			t.Run(fmt.Sprintf("grade_%d_%s", test.grade, channel), func(t *testing.T) {
				profile := ResolveCommunicationProfile(test.grade, channel)
				if profile.GradeBand != test.band || string(profile.Channel) != channel {
					t.Fatalf("unexpected profile: %#v", profile)
				}
				if !strings.Contains(profile.Role, test.rolePart) || !strings.Contains(profile.ResponseShape, test.shapePart) {
					t.Fatalf("profile does not implement product matrix: %#v", profile)
				}
				analysis := service.Analyze("Объясни тему", test.grade, false)
				prompt := service.BuildPromptForChannel("Объясни тему", test.grade, analysis, "none", "none", channel)
				if !strings.Contains(prompt, "Authenticated grade: "+fmt.Sprint(test.grade)+" ("+test.band+")") ||
					!strings.Contains(prompt, "Communication channel: "+channel) {
					t.Fatalf("prompt misses age/channel contract:\n%s", prompt)
				}
				if channel == "voice" {
					if profile.MaximumRunes != test.voiceMax || !strings.Contains(prompt, "no headings, bullet lists, tables") {
						t.Fatalf("voice contract is not bounded/conversational: %#v", profile)
					}
				} else if profile.MaximumRunes != 4_000 {
					t.Fatalf("text compatibility cap changed: %#v", profile)
				}
			})
		}
	}
}

func TestDifficultySignalsUseCalmSpecificSupportWithoutSecondClassification(t *testing.T) {
	service := NewService()
	for _, text := range []string{"Я не понимаю дроби", "У меня не получается", "Маған қиын", "Мен түсінбеймін"} {
		analysis := service.Analyze(text, 7, false)
		if !analysis.NeedsCalmSupport {
			t.Fatalf("difficulty signal was missed: %q", text)
		}
		prompt := service.BuildPromptForChannel(text, 7, analysis, "none", "none", "text")
		if !strings.Contains(prompt, "reduce the task to the next manageable action") || !strings.Contains(prompt, "praise only specific observed effort") {
			t.Fatalf("support contract missing for %q:\n%s", text, prompt)
		}
	}
}

func TestRUAndKKScenarioMatrixForTextAndVoice(t *testing.T) {
	type scenario struct {
		name        string
		grade       int
		ru          string
		kk          string
		rawRU       string
		rawKK       string
		wantIntent  Intent
		wantEmotion string
		activeHW    bool
		safety      bool
	}
	scenarios := []scenario{
		{"topic explanation", 1, "Объясни, почему идёт дождь", "Жаңбыр неге жауатынын түсіндір", "Вода поднимается в облака, а потом падает каплями.", "Су бұлтқа көтеріліп, кейін тамшы болып түседі.", IntentConceptExplanation, "surprised", false, false},
		{"first homework hint", 3, "Помоги с домашним заданием подсказкой", "Үй тапсырмасына бір ишара бер", "Сначала назови известные данные.", "Алдымен белгілі деректерді ата.", IntentHomeworkHelp, "neutral", true, false},
		{"incorrect attempt", 6, "Проверь мой ответ: x = 4", "Менің жауабымды тексер: x = 4", "Здесь ошибка: проверь обратной подстановкой.", "Мұнда қате бар: орнына қойып тексер.", IntentCheckStudentAttempt, "sorrow", true, false},
		{"correct attempt", 8, "Проверь мой ответ: x = 5", "Менің жауабымды тексер: x = 5", "Верно: подстановка подтверждает результат.", "Дұрыс: орнына қою нәтижені растайды.", IntentCheckStudentAttempt, "joy", true, false},
		{"struggle", 11, "Я не понимаю эту тему", "Мен бұл тақырыпты түсінбеймін", "Начнём с одного определения и проверим его на примере.", "Бір анықтамадан бастап, оны мысалмен тексерейік.", IntentGeneralQuestion, "sorrow", false, false},
		{"ready answer", 7, "Дай готовый ответ для сдачи", "Маған дайын жауап бер", "Готовый ответ: 42.", "Дайын жауап: 42.", IntentRequestReadyAnswer, "neutral", true, false},
		{"ordinary question", 4, "Столица Франции?", "Францияның астанасы қай қала?", "Париж.", "Париж.", IntentGeneralQuestion, "neutral", false, false},
		{"light general chat", 9, "Привет, как дела?", "Сәлем, қалайсың?", "Привет! Я рядом и готова помочь.", "Сәлем! Мен осындамын, көмектесуге дайынмын.", IntentGeneralQuestion, "fun", false, false},
		{"safety response", 10, "Опасный запрос", "Қауіпті сұрау", "Я не могу с этим помочь.", "Бұған көмектесе алмаймын.", IntentGeneralQuestion, "sorrow", false, true},
	}

	service := NewService()
	for _, scenario := range scenarios {
		for _, language := range []string{"ru", "kk"} {
			for _, channel := range []string{"text", "voice"} {
				t.Run(scenario.name+"_"+language+"_"+channel, func(t *testing.T) {
					question, raw := scenario.ru, scenario.rawRU
					if language == "kk" {
						question, raw = scenario.kk, scenario.rawKK
					}
					analysis := service.Analyze(question, scenario.grade, scenario.activeHW)
					if scenario.safety {
						analysis.ResponseMode = ResponseModeSafety
						analysis.HelpLevel = "safety"
					}
					if analysis.Intent != scenario.wantIntent {
						t.Fatalf("intent mismatch: got %s want %s (%#v)", analysis.Intent, scenario.wantIntent, analysis)
					}
					prompt := service.BuildPromptForChannel(question, scenario.grade, analysis, "none", "none", channel)
					if !strings.Contains(prompt, "Communication channel: "+channel) || !strings.Contains(prompt, "("+GradeBand(scenario.grade)+")") {
						t.Fatalf("prompt lacks scenario delivery contract:\n%s", prompt)
					}
					draft := service.FinalizeForChannel(raw, analysis, language, channel)
					if draft.Emotion != scenario.wantEmotion || draft.EmotionIntensity < 0 || draft.EmotionIntensity > 1 {
						t.Fatalf("unexpected emotion: %#v", draft)
					}
					if channel == "voice" && (strings.Contains(draft.Answer, "\n") || len([]rune(draft.Answer)) > ResolveCommunicationProfile(scenario.grade, channel).MaximumRunes) {
						t.Fatalf("voice answer is not flattened/bounded: %#v", draft)
					}
					if scenario.name == "ready answer" && (!draft.ReadyAnswerRisk || strings.Contains(draft.Answer, "42")) {
						t.Fatalf("ready-answer policy weakened: %#v", draft)
					}
				})
			}
		}
	}
}

func TestVoiceBoundsKeepOnlyCompletedSentencesInRUAndKK(t *testing.T) {
	tests := []struct {
		name       string
		grade      int
		language   string
		completed  string
		unfinished string
	}{
		{"grade_1_ru", 1, "ru", "Сначала найдём одно известное число.", " Затем продолжим рассуждение без завершения"},
		{"grade_1_kk", 1, "kk", "Алдымен бір белгілі санды табамыз.", " Содан кейін аяқталмаған талдауды жалғастырамыз"},
		{"grade_11_ru", 11, "ru", "Сначала зафиксируем допущение и критерий проверки аргумента.", " Затем разовьём незавершённую аргументацию без итоговой точки"},
		{"grade_11_kk", 11, "kk", "Алдымен болжам мен дәлелді тексеру критерийін белгілейміз.", " Содан кейін қорытынды нүктесіз аяқталмаған дәлелдеуді жалғастырамыз"},
	}
	service := NewService()
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			analysis := service.Analyze("Объясни тему", test.grade, false)
			limit := ResolveCommunicationProfile(test.grade, "voice").MaximumRunes
			raw := test.completed + strings.Repeat(test.unfinished, limit)
			draft := service.FinalizeForChannel(raw, analysis, test.language, "voice")
			if draft.Answer != test.completed {
				t.Fatalf("voice bound exposed an incomplete fragment: got %q want %q", draft.Answer, test.completed)
			}
			if len([]rune(draft.Answer)) > limit {
				t.Fatalf("voice answer exceeds %d runes: %q", limit, draft.Answer)
			}
		})
	}
}

func TestVoiceBoundsUseCompletedLocalizedFallbackWithoutSentenceBoundary(t *testing.T) {
	service := NewService()
	for _, test := range []struct {
		grade    int
		language string
		prefix   string
	}{
		{1, "ru", "Начнём с одного шага."},
		{1, "kk", "Бір қадамнан бастайық."},
		{11, "ru", "Сформулируем короче."},
		{11, "kk", "Қысқаша тұжырымдайық."},
	} {
		analysis := service.Analyze("Объясни тему", test.grade, false)
		limit := ResolveCommunicationProfile(test.grade, "voice").MaximumRunes
		raw := strings.Repeat("длинная фраза без точки ", limit)
		draft := service.FinalizeForChannel(raw, analysis, test.language, "voice")
		if !strings.HasPrefix(draft.Answer, test.prefix) ||
			!(strings.HasSuffix(draft.Answer, ".") || strings.HasSuffix(draft.Answer, "?")) ||
			len([]rune(draft.Answer)) > limit {
			t.Fatalf("localized fallback is incomplete or unbounded: grade=%d language=%s answer=%q", test.grade, test.language, draft.Answer)
		}
	}
}
