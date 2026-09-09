package gamification

const CatalogVersion = 1

type LocalizedText struct {
	RU string `json:"ru"`
	KK string `json:"kk"`
}

type Definition struct {
	Code        string
	Category    string
	Title       LocalizedText
	Description LocalizedText
	Metric      Metric
	Target      int
}

type Metric string

const (
	MetricActiveDays        Metric = "active_days"
	MetricLongestStreak     Metric = "longest_streak"
	MetricGradeFives        Metric = "grade_fives"
	MetricLearningQuestions Metric = "learning_questions"
	MetricAttemptChecks     Metric = "attempt_checks"
)

var categoryTitles = map[string]LocalizedText{
	"activity":     {RU: "Активность", KK: "Белсенділік"},
	"grades":       {RU: "Оценки", KK: "Бағалар"},
	"learning":     {RU: "Обучение с Kundi", KK: "Kundi-мен оқу"},
	"independence": {RU: "Самостоятельность", KK: "Өз бетінше жұмыс"},
}

var catalog = []Definition{
	{Code: "activity_first_day", Category: "activity", Title: LocalizedText{RU: "Первый день", KK: "Алғашқы күн"}, Description: LocalizedText{RU: "Впервые воспользуйся Kundi.", KK: "Kundi қолданбасын алғаш рет пайдалан."}, Metric: MetricActiveDays, Target: 1},
	{Code: "activity_streak_3", Category: "activity", Title: LocalizedText{RU: "Ритм", KK: "Ырғақ"}, Description: LocalizedText{RU: "Пользуйся Kundi 3 дня подряд.", KK: "Kundi қолданбасын 3 күн қатарынан пайдалан."}, Metric: MetricLongestStreak, Target: 3},
	{Code: "activity_streak_7", Category: "activity", Title: LocalizedText{RU: "Старательный", KK: "Талапты"}, Description: LocalizedText{RU: "Пользуйся Kundi 7 дней подряд.", KK: "Kundi қолданбасын 7 күн қатарынан пайдалан."}, Metric: MetricLongestStreak, Target: 7},
	{Code: "activity_streak_30", Category: "activity", Title: LocalizedText{RU: "Месяц вместе", KK: "Бір ай бірге"}, Description: LocalizedText{RU: "Пользуйся Kundi 30 дней подряд.", KK: "Kundi қолданбасын 30 күн қатарынан пайдалан."}, Metric: MetricLongestStreak, Target: 30},
	{Code: "grade_five_1", Category: "grades", Title: LocalizedText{RU: "Первая пятёрка", KK: "Алғашқы бестік"}, Description: LocalizedText{RU: "Получи первую обычную оценку «5».", KK: "Алғашқы күнделікті «5» бағаңды ал."}, Metric: MetricGradeFives, Target: 1},
	{Code: "grade_five_5", Category: "grades", Title: LocalizedText{RU: "Пять пятёрок", KK: "Бес бестік"}, Description: LocalizedText{RU: "Получи 5 обычных оценок «5».", KK: "Күнделікті 5 рет «5» бағасын ал."}, Metric: MetricGradeFives, Target: 5},
	{Code: "grade_five_10", Category: "grades", Title: LocalizedText{RU: "Отличник", KK: "Үздік оқушы"}, Description: LocalizedText{RU: "Получи 10 обычных оценок «5».", KK: "Күнделікті 10 рет «5» бағасын ал."}, Metric: MetricGradeFives, Target: 10},
	{Code: "learning_question_1", Category: "learning", Title: LocalizedText{RU: "Первый вопрос", KK: "Алғашқы сұрақ"}, Description: LocalizedText{RU: "Задай Kundi первый учебный вопрос.", KK: "Kundi-ге алғашқы оқу сұрағыңды қой."}, Metric: MetricLearningQuestions, Target: 1},
	{Code: "learning_question_10", Category: "learning", Title: LocalizedText{RU: "Любознательный", KK: "Білімқұмар"}, Description: LocalizedText{RU: "Задай Kundi 10 учебных вопросов.", KK: "Kundi-ге 10 оқу сұрағын қой."}, Metric: MetricLearningQuestions, Target: 10},
	{Code: "learning_question_50", Category: "learning", Title: LocalizedText{RU: "Исследователь", KK: "Зерттеуші"}, Description: LocalizedText{RU: "Задай Kundi 50 учебных вопросов.", KK: "Kundi-ге 50 оқу сұрағын қой."}, Metric: MetricLearningQuestions, Target: 50},
	{Code: "attempt_check_1", Category: "independence", Title: LocalizedText{RU: "Первая попытка", KK: "Алғашқы талпыныс"}, Description: LocalizedText{RU: "Отправь первую самостоятельную попытку на проверку.", KK: "Алғашқы өздік талпынысыңды тексеруге жібер."}, Metric: MetricAttemptChecks, Target: 1},
	{Code: "attempt_check_5", Category: "independence", Title: LocalizedText{RU: "Самостоятельный", KK: "Өз бетімен"}, Description: LocalizedText{RU: "Проверь 5 самостоятельных попыток.", KK: "5 өздік талпынысыңды тексер."}, Metric: MetricAttemptChecks, Target: 5},
	{Code: "attempt_check_20", Category: "independence", Title: LocalizedText{RU: "Уверенный", KK: "Сенімді"}, Description: LocalizedText{RU: "Проверь 20 самостоятельных попыток.", KK: "20 өздік талпынысыңды тексер."}, Metric: MetricAttemptChecks, Target: 20},
}

func Catalog() []Definition {
	return append([]Definition(nil), catalog...)
}

func CategoryTitle(code string) LocalizedText { return categoryTitles[code] }

var levelThresholds = []int{0, 100, 250, 500, 900, 1400, 2100, 3000, 4200, 5700}

func LevelForPoints(points int) (level, floor, next int) {
	if points < 0 {
		points = 0
	}
	level = 1
	for index, threshold := range levelThresholds {
		if points < threshold {
			break
		}
		level = index + 1
		floor = threshold
	}
	if level < len(levelThresholds) {
		next = levelThresholds[level]
	} else {
		next = floor
	}
	return level, floor, next
}
