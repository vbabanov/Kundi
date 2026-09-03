package safety

import (
	"context"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

type phraseRule struct {
	phrases  []string
	category SafetyCategory
	risk     RiskLevel
}

type Policy struct {
	rules []phraseRule
}

func NewPolicy() *Policy {
	return &Policy{rules: []phraseRule{
		{
			category: CategorySelfHarm,
			risk:     RiskImmediate,
			phrases: []string{
				"i want to kill myself", "i am going to kill myself", "i want to hurt myself", "i do not want to live anymore",
				"я хочу убить себя", "я собираюсь убить себя", "хочу покончить с собой", "я не хочу больше жить",
				"өзімді өлтіргім келеді", "өзіме қол жұмсағым келеді", "өмір сүргім келмейді",
			},
		},
		{
			category: CategoryViolenceOrAbuse,
			risk:     RiskImmediate,
			phrases: []string{
				"someone is hurting me right now", "i am being hit right now",
				"меня сейчас бьют", "мне сейчас угрожают",
				"мені қазір ұрып жатыр", "маған қазір қауіп төніп тұр",
			},
		},
		{
			category: CategoryViolenceOrAbuse,
			risk:     RiskHarmful,
			phrases: []string{
				"how to kill someone", "how can i seriously hurt someone",
				"как убить человека", "как сильно покалечить человека",
				"адамды қалай өлтіруге болады", "адамды қалай ауыр жаралауға болады",
			},
		},
		{
			category: CategoryBullying,
			risk:     RiskImmediate,
			phrases: []string{
				"i am being bullied", "they bully me at school",
				"меня травят", "меня травят в школе",
				"мені мектепте қорлайды", "мені мазақтап жүр",
			},
		},
		{
			category: CategorySexualSafety,
			risk:     RiskImmediate,
			phrases: []string{
				"an adult asked me for a nude photo", "an adult is asking me for naked pictures",
				"взрослый просит у меня голое фото", "взрослый просит прислать интимное фото",
				"ересек адам менен жалаңаш сурет сұрады", "ересек адам интим сурет жіберуді сұрады",
			},
		},
		{
			category: CategoryDangerousOrIllegal,
			risk:     RiskHarmful,
			phrases: []string{
				"how to make a bomb", "how to poison someone", "how to hack an account",
				"как сделать бомбу", "как отравить человека", "как взломать аккаунт",
				"бомбаны қалай жасауға болады", "адамды қалай улауға болады", "аккаунтты қалай бұзуға болады",
			},
		},
		{
			category: CategoryMedicalHighStakes,
			risk:     RiskHarmful,
			phrases: []string{
				"what dose of medicine should i take", "tell me how many pills to take",
				"какую дозу лекарства мне принять", "скажи сколько таблеток мне выпить",
				"дәрінің қандай дозасын ішуім керек", "қанша таблетка ішуім керек",
			},
		},
		{
			category: CategoryPrivacyOrSecrets,
			risk:     RiskHarmful,
			phrases: []string{
				"my password is", "here is my bank card number",
				"мой пароль это", "вот мой пароль", "вот номер моей банковской карты",
				"менің құпиясөзім мынау", "менің банк картамның нөмірі",
			},
		},
		{
			category: CategoryHarassment,
			risk:     RiskHarmful,
			phrases: []string{
				"write a threat to", "write a cruel insult for",
				"напиши угрозу для", "напиши жестокое оскорбление",
				"қорқыту мәтінін жаз", "қатты қорлайтын сөз жаз",
			},
		},
	}}
}

func (p *Policy) Moderate(ctx context.Context, text string) (ModerationResult, error) {
	if err := ctx.Err(); err != nil {
		return ModerationResult{}, err
	}
	trimmed := strings.TrimSpace(text)
	language := DetectLanguage(trimmed)
	normalized := normalizeForMatching(trimmed)
	for _, rule := range p.rules {
		for _, phrase := range rule.phrases {
			if strings.Contains(normalized, normalizeForMatching(phrase)) {
				return ModerationResult{
					Allowed:       false,
					Category:      rule.category,
					Risk:          rule.risk,
					Language:      language,
					ReasonCode:    "deterministic_" + string(rule.category),
					SanitizedText: trimmed,
				}, nil
			}
		}
	}
	return ModerationResult{
		Allowed:       true,
		Category:      CategoryNone,
		Risk:          RiskInformational,
		Language:      language,
		ReasonCode:    "allowed",
		SanitizedText: trimmed,
	}, nil
}

func normalizeForMatching(text string) string {
	normalized := norm.NFKC.String(strings.ToLower(strings.TrimSpace(text)))
	var out strings.Builder
	for _, r := range normalized {
		if unicode.IsLetter(r) || unicode.IsNumber(r) {
			out.WriteRune(r)
			continue
		}
		out.WriteByte(' ')
	}
	return strings.Join(strings.Fields(out.String()), " ")
}

func DetectLanguage(text string) Language {
	hasCyrillic := false
	for _, r := range strings.ToLower(text) {
		if strings.ContainsRune("әғқңөұүһі", r) {
			return LanguageKazakh
		}
		if unicode.In(r, unicode.Cyrillic) {
			hasCyrillic = true
		}
	}
	if hasCyrillic {
		return LanguageRussian
	}
	return LanguageEnglish
}
