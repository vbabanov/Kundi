package homeinsight

import (
	"crypto/sha256"
	"encoding/binary"
	"strings"
	"time"

	"github.com/google/uuid"
)

const CatalogVersion = 1

type Kind string

const (
	KindStudyTip   Kind = "study_tip"
	KindDidYouKnow Kind = "did_you_know"
)

type GradeBand string

const (
	GradeBandPrimary GradeBand = "primary"
	GradeBandMiddle  GradeBand = "middle"
	GradeBandSenior  GradeBand = "senior"
)

type LocalizedText struct {
	RU string
	KK string
}

func (text LocalizedText) Resolve(locale string) string {
	if locale == "kk" {
		return strings.TrimSpace(text.KK)
	}
	return strings.TrimSpace(text.RU)
}

type CatalogItem struct {
	ID         string
	Kind       Kind
	Bands      []GradeBand
	Text       LocalizedText
	EvidenceID string
}

var curatedCatalog = []CatalogItem{
	{
		ID: "primary_read_then_mark_v1", Kind: KindStudyTip,
		Bands: []GradeBand{GradeBandPrimary},
		Text: LocalizedText{
			RU: "Прочитай условие дважды, а потом отметь, что уже известно и что нужно найти.",
			KK: "Есептің шартын екі рет оқып, содан кейін не белгілі және нені табу керегін белгіле.",
		},
	},
	{
		ID: "primary_small_step_v1", Kind: KindStudyTip,
		Bands: []GradeBand{GradeBandPrimary},
		Text: LocalizedText{
			RU: "Если задание кажется большим, начни с одного понятного шага.",
			KK: "Тапсырма үлкен болып көрінсе, бір түсінікті қадамнан баста.",
		},
	},
	{
		ID: "primary_retrieval_v1", Kind: KindDidYouKnow,
		Bands: []GradeBand{GradeBandPrimary}, EvidenceID: "dunlosky-2013-practice-testing",
		Text: LocalizedText{
			RU: "Попытка вспомнить изученное без подсказки помогает закрепить материал лучше, чем одно перечитывание.",
			KK: "Оқығаныңды көмексіз еске түсіруге тырысу материалды жай қайта оқудан жақсырақ бекітуге көмектеседі.",
		},
	},
	{
		ID: "middle_explain_rule_v1", Kind: KindStudyTip,
		Bands: []GradeBand{GradeBandMiddle},
		Text: LocalizedText{
			RU: "Попробуй объяснить правило своими словами — так легче заметить пробел.",
			KK: "Ережені өз сөзіңмен түсіндіріп көр — осылай түсінбеген жерді байқау оңайырақ.",
		},
	},
	{
		ID: "middle_known_condition_v1", Kind: KindStudyTip,
		Bands: []GradeBand{GradeBandMiddle},
		Text: LocalizedText{
			RU: "Большую задачу проще начать с одного известного условия.",
			KK: "Күрделі есепті белгілі бір шарттан бастау оңайырақ.",
		},
	},
	{
		ID: "middle_spacing_v1", Kind: KindDidYouKnow,
		Bands: []GradeBand{GradeBandMiddle}, EvidenceID: "dunlosky-2013-distributed-practice",
		Text: LocalizedText{
			RU: "Повторение через короткие интервалы обычно помогает помнить тему дольше, чем одно длинное занятие.",
			KK: "Қысқа аралықтармен қайталау бір ұзақ дайындықтан гөрі тақырыпты ұзақ есте сақтауға көмектеседі.",
		},
	},
	{
		ID: "senior_plan_variables_v1", Kind: KindStudyTip,
		Bands: []GradeBand{GradeBandSenior},
		Text: LocalizedText{
			RU: "Перед решением выпиши данные, неизвестные и связь между ними — это часто проясняет первый шаг.",
			KK: "Шешуге кіріспес бұрын берілгендерді, белгісіздерді және олардың байланысын жаз — бұл алғашқы қадамды айқындайды.",
		},
	},
	{
		ID: "senior_compare_methods_v1", Kind: KindStudyTip,
		Bands: []GradeBand{GradeBandSenior},
		Text: LocalizedText{
			RU: "После решения сравни два возможных способа: короткая проверка помогает увидеть лишние шаги.",
			KK: "Шешкеннен кейін екі тәсілді салыстыр: қысқа тексеру артық қадамдарды байқауға көмектеседі.",
		},
	},
	{
		ID: "senior_interleaving_v1", Kind: KindDidYouKnow,
		Bands: []GradeBand{GradeBandSenior}, EvidenceID: "rohrer-taylor-2007-interleaving",
		Text: LocalizedText{
			RU: "Чередование задач разных типов может улучшать результат отсроченной проверки по сравнению с решением блоками одного типа.",
			KK: "Әртүрлі типтегі есептерді кезектестіру бір типті есептерді топтап шешумен салыстырғанда кейінгі тексеру нәтижесін жақсарта алады.",
		},
	},
	{
		ID: "all_self_explanation_v1", Kind: KindDidYouKnow,
		Bands: []GradeBand{GradeBandPrimary, GradeBandMiddle, GradeBandSenior}, EvidenceID: "chi-1989-self-explanation",
		Text: LocalizedText{
			RU: "Объяснение каждого шага самому себе помогает глубже понять решение, а не только запомнить ответ.",
			KK: "Әр қадамды өзіңе түсіндіру тек жауапты жаттап қоймай, шешімді тереңірек түсінуге көмектеседі.",
		},
	},
}

func Catalog() []CatalogItem {
	result := make([]CatalogItem, len(curatedCatalog))
	for index, item := range curatedCatalog {
		result[index] = item
		result[index].Bands = append([]GradeBand(nil), item.Bands...)
	}
	return result
}

func BandForGrade(gradeLevel int) GradeBand {
	switch {
	case gradeLevel >= 1 && gradeLevel <= 4:
		return GradeBandPrimary
	case gradeLevel >= 9:
		return GradeBandSenior
	default:
		return GradeBandMiddle
	}
}

func itemsForBand(catalog []CatalogItem, band GradeBand) []CatalogItem {
	result := make([]CatalogItem, 0, len(catalog))
	for _, item := range catalog {
		for _, supported := range item.Bands {
			if supported == band {
				result = append(result, item)
				break
			}
		}
	}
	return result
}

func selectItem(catalog []CatalogItem, studentID uuid.UUID, day time.Time, band GradeBand) CatalogItem {
	candidates := itemsForBand(catalog, band)
	if len(candidates) == 0 {
		candidates = itemsForBand(curatedCatalog, GradeBandMiddle)
	}
	seed := studentID.String() + "|" + day.Format("2006-01-02") + "|" + string(band) + "|daily"
	digest := sha256.Sum256([]byte(seed))
	index := binary.BigEndian.Uint64(digest[:8]) % uint64(len(candidates))
	return candidates[index]
}
