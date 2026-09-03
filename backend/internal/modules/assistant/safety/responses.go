package safety

type SafeResponse struct {
	Text     string
	Category SafetyCategory
	Language Language
}

type SafeResponseFactory struct{}

func NewSafeResponseFactory() *SafeResponseFactory {
	return &SafeResponseFactory{}
}

func (f *SafeResponseFactory) ForModeration(result ModerationResult) SafeResponse {
	language := result.Language
	if language == "" {
		language = LanguageEnglish
	}
	if result.Risk == RiskImmediate || result.Category == CategorySelfHarm || result.Category == CategoryBullying || result.Category == CategorySexualSafety {
		return immediateSafetyResponse(language, result.Category)
	}
	if result.Category == CategoryMedicalHighStakes {
		return localizedResponse(language, result.Category,
			"Я не могу безопасно подбирать дозу лекарства. Обратись к взрослому, которому доверяешь, и к медицинскому специалисту. Могу помочь составить вопросы для них.",
			"Дәрінің дозасын қауіпсіз түрде таңдай алмаймын. Сенетін ересек адамға және медицина маманына хабарлас. Оларға қоятын сұрақтарды дайындауға көмектесе аламын.",
			"I cannot safely choose a medicine dose. Please ask a trusted adult and a medical professional. I can help you prepare questions for them.")
	}
	if result.Category == CategoryPrivacyOrSecrets {
		return localizedResponse(language, result.Category,
			"Не отправляй сюда пароли, данные карты или другие секреты. Удали их из сообщения и спроси снова без личных данных.",
			"Мұнда құпиясөздерді, карта деректерін немесе басқа құпияларды жіберме. Оларды хабарламадан алып тастап, жеке деректерсіз қайта сұра.",
			"Do not share passwords, card details, or other secrets here. Remove them and ask again without personal information.")
	}
	return localizedResponse(language, result.Category,
		"Я не могу помогать с опасными или вредными действиями. Могу объяснить тему безопасно или предложить безвредную альтернативу.",
		"Қауіпті немесе зиянды әрекеттерге көмектесе алмаймын. Тақырыпты қауіпсіз түсіндіре аламын немесе зиянсыз балама ұсына аламын.",
		"I cannot help with dangerous or harmful actions. I can explain the topic safely or suggest a harmless alternative.")
}

func (f *SafeResponseFactory) ForModerationFailure(language Language) SafeResponse {
	return localizedResponse(language, CategoryUnknownRisk,
		"Сейчас я не могу надёжно проверить безопасность ответа. Попробуй позже или обратись к учителю или взрослому, которому доверяешь.",
		"Қазір жауаптың қауіпсіздігін сенімді тексере алмаймын. Кейінірек қайталап көр немесе мұғалімге не сенетін ересек адамға хабарлас.",
		"I cannot reliably check the safety of this response right now. Please try later or ask a teacher or trusted adult.")
}

func (f *SafeResponseFactory) ForProviderFailure(language Language) SafeResponse {
	return localizedResponse(language, CategoryUnknownRisk,
		"Сейчас я не могу надёжно ответить. Попробуй ещё раз позже или обратись к учителю.",
		"Қазір сенімді жауап бере алмаймын. Кейінірек қайталап көр немесе мұғалімнен сұра.",
		"I cannot give a reliable answer right now. Please try again later or ask a teacher.")
}

func (f *SafeResponseFactory) ForRateLimit(language Language) SafeResponse {
	return localizedResponse(language, CategoryNone,
		"Слишком много сообщений за короткое время. Подожди немного и попробуй снова.",
		"Қысқа уақытта тым көп хабарлама жіберілді. Біраз күтіп, қайта көр.",
		"There have been too many messages in a short time. Please wait a little and try again.")
}

func immediateSafetyResponse(language Language, category SafetyCategory) SafeResponse {
	return localizedResponse(language, category,
		"Мне жаль, что ты с этим столкнулся. Прямо сейчас обратись к взрослому, которому доверяешь. Если опасность непосредственная, позвони в местные экстренные службы.",
		"Мұндай жағдайға тап болғаныңа өкінемін. Дәл қазір сенетін ересек адамға айт. Егер қауіп тікелей болса, жергілікті жедел қызметке қоңырау шал.",
		"I am sorry you are facing this. Tell a trusted adult right now. If the danger is immediate, call your local emergency services.")
}

func localizedResponse(language Language, category SafetyCategory, russian, kazakh, english string) SafeResponse {
	switch language {
	case LanguageKazakh:
		return SafeResponse{Text: kazakh, Category: category, Language: language}
	case LanguageRussian:
		return SafeResponse{Text: russian, Category: category, Language: language}
	default:
		return SafeResponse{Text: english, Category: category, Language: LanguageEnglish}
	}
}
