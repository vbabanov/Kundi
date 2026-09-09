// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Kundi';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonContinue => 'Продолжить';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get commonRefresh => 'Обновить';

  @override
  String get commonSend => 'Отправить';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonNotSpecified => 'Не указано';

  @override
  String get commonNoData => 'Нет данных';

  @override
  String get commonLoading => 'Загрузка';

  @override
  String get commonSoon => 'Скоро';

  @override
  String get commonYear => 'Год';

  @override
  String get navHomework => 'ДЗ';

  @override
  String get navHome => 'Главная';

  @override
  String get navGrades => 'Оценки';

  @override
  String get authLoginFailed => 'Не удалось войти. Попробуйте ещё раз.';

  @override
  String get authLoginSuccess => 'Вход выполнен';

  @override
  String authViaProvider(String provider) {
    return 'Вход через $provider';
  }

  @override
  String get authDiaryCredentials => 'Логин и пароль от электронного дневника';

  @override
  String get authLogin => 'Логин';

  @override
  String get authPassword => 'Пароль';

  @override
  String get authContinue => 'Продолжить';

  @override
  String get authYourDiary => 'Ваш электронный дневник';

  @override
  String get authWith => 'с ';

  @override
  String get authAiTutor => 'ИИ-репетитором';

  @override
  String get authHello => 'Привет!';

  @override
  String get authIAm => 'Я ';

  @override
  String get authTutorSuffix => ', ваш\nИИ-репетитор';

  @override
  String get authSignInPrefix => 'Войдите через ваш\n';

  @override
  String get authElectronicDiary => 'электронный дневник';

  @override
  String get authChooseService => 'Выберите сервис для входа';

  @override
  String get authKundelik => 'Войти через Kundelik.kz';

  @override
  String get authDnevnik => 'Войти через Dnevnik.ru';

  @override
  String get authEduPage => 'Войти через EduPage';

  @override
  String get authSecure => 'Безопасно и надёжно';

  @override
  String get authPasswordNotStored => 'Мы не храним пароль от дневника';

  @override
  String get homeTitle => 'Главная';

  @override
  String get homeGoodMorning => 'Доброе утро';

  @override
  String get homeGoodAfternoon => 'Добрый день';

  @override
  String get homeGoodEvening => 'Добрый вечер';

  @override
  String get homeGoodNight => 'Доброй ночи';

  @override
  String homeGreeting(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get homeProfileTooltip => 'Профиль';

  @override
  String get homeKundiCharacter => 'Персонаж Kundi';

  @override
  String get homePlanAvailable => 'План на сегодня доступен';

  @override
  String get homePlanEmpty => 'План на сегодня пока пуст';

  @override
  String get homeHomeworkToday => 'ДЗ сегодня';

  @override
  String get homeHomeworkWeek => 'ДЗ за неделю';

  @override
  String get homeAttendance => 'Посещаемость';

  @override
  String get homeAvailableData => 'Показываем доступные данные';

  @override
  String get homeAskKundi => 'Спросите Kundi...';

  @override
  String get homeAssistantDescription =>
      'Объяснит тему и поможет сделать первый шаг';

  @override
  String get homeAssistantSoon => 'Персональный помощник появится позже';

  @override
  String get homeNearestLesson => 'Ближайший урок';

  @override
  String get homeNoLessons => 'Нет уроков';

  @override
  String get homeNoAssignments => 'Нет заданий';

  @override
  String get homeBuildingPlan => 'Собираю твой план на сегодня.';

  @override
  String get homeScheduleUnavailable =>
      'Расписание временно недоступно. Попробуем обновить ещё раз.';

  @override
  String get homeSeeTodayPlan =>
      'Давай посмотрим, что запланировано на сегодня.';

  @override
  String homeTodayLessons(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count урока',
      many: '$count уроков',
      few: '$count урока',
      one: '$count урок',
    );
    return 'Сегодня у тебя $_temp0.';
  }

  @override
  String homeNearestSubject(String subject) {
    return 'Ближайший — $subject.';
  }

  @override
  String homeTodayHomework(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count задания',
      many: '$count заданий',
      few: '$count задания',
      one: '$count задание',
    );
    return 'На сегодня $_temp0.';
  }

  @override
  String get homeNoHomeworkToday => 'Заданий на сегодня нет';

  @override
  String homeHomeworkTodayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count задания',
      many: '$count заданий',
      few: '$count задания',
      one: '$count задание',
    );
    return '$_temp0 на сегодня';
  }

  @override
  String get homeNoNewGrades => 'Новых оценок нет';

  @override
  String get homeLatestResults => 'Последние результаты';

  @override
  String get homeLatestGrades => 'Последние оценки';

  @override
  String get homeKundiCelebrating => 'Отличная работа!';

  @override
  String get homeKundiCelebratingSemantic => 'Kundi радуется успеху';

  @override
  String get homeKundiThinking => 'Думаю…';

  @override
  String get homeKundiThinkingSemantic => 'Kundi думает';

  @override
  String get homeKundiSpeaking => 'Ответ появится здесь позже.';

  @override
  String get homeKundiSpeakingSemantic => 'Kundi готовит ответ';

  @override
  String get homeKundiListening => 'Я слушаю';

  @override
  String get homeKundiListeningSemantic => 'Kundi слушает';

  @override
  String get homeKundiWarning =>
      'Давай спокойно проверим, что требует внимания.';

  @override
  String get homeKundiWarningSemantic => 'Kundi предлагает проверить важное';

  @override
  String get homeKundiError => 'Что-то пошло не так. Попробуем ещё раз позже.';

  @override
  String get homeKundiErrorSemantic => 'Kundi временно недоступен';

  @override
  String get profileTitle => 'Профиль';

  @override
  String get profileNotLoaded => 'Профиль ещё не загружен';

  @override
  String get profileLoading => 'Загружаю профиль...';

  @override
  String get profileLoadFailed => 'Не удалось загрузить профиль';

  @override
  String get profileSaved => 'Профиль сохранён';

  @override
  String get profileSaveFailed =>
      'Не удалось сохранить профиль. Попробуйте ещё раз.';

  @override
  String get profilePhotoSoon => 'Добавление фото появится позже';

  @override
  String get profileLogoutTitle => 'Выйти из аккаунта?';

  @override
  String get profileLogoutBody =>
      'Вы выйдете из текущего профиля на этом устройстве.';

  @override
  String get profileLogout => 'Выйти';

  @override
  String get profileStudentData => 'Данные ученика';

  @override
  String get profileParentContacts => 'Контакты родителей';

  @override
  String get profileStudent => 'Ученик';

  @override
  String get profileInitials => 'ПР';

  @override
  String get profilePoints => 'Баллы';

  @override
  String get profileStreak => 'Дней подряд';

  @override
  String get profileLevel => 'Уровень';

  @override
  String get profileSchool => 'Школа';

  @override
  String get profileClass => 'Класс';

  @override
  String get profileShift => 'Смена';

  @override
  String get profileShiftOne => '1 смена';

  @override
  String get profileShiftTwo => '2 смена';

  @override
  String get profileShiftUnknown => '—';

  @override
  String get profileTeacher => 'Классный руководитель';

  @override
  String get profileContactsHelp =>
      'Оставьте номера родителей, чтобы школа могла быстро связаться при необходимости.';

  @override
  String get profileParentPhoneOne => 'Номер родителя 1';

  @override
  String get profileParentPhoneOneRequired => 'Введите номер родителя 1';

  @override
  String get profileParentPhoneTwo => 'Номер родителя 2 (необязательно)';

  @override
  String get profilePhoneOptionalHint => 'Введите номер (необязательно)';

  @override
  String get profilePhoneInvalid => 'Номер должен содержать от 10 до 15 цифр';

  @override
  String get profileSaveChanges => 'Сохранить изменения';

  @override
  String get profileAchievements => 'Достижения';

  @override
  String get profileAllAchievements => 'Все достижения';

  @override
  String get profileAchievementExcellent => 'Отличник';

  @override
  String get profileAchievementExcellentHint => '10 отличных\nоценок';

  @override
  String get profileAchievementDiligent => 'Старательный';

  @override
  String get profileAchievementDiligentHint => '7 дней подряд\nактивности';

  @override
  String get profileAchievementCurious => 'Любознательный';

  @override
  String get profileAchievementCuriousHint => '50 заданий\nвыполнено';

  @override
  String get profileAchievementFirstFive => 'Первая пятёрка';

  @override
  String get profileAchievementFirstFiveHint => 'Получите 5 оценок\n«5»';

  @override
  String get gamificationLoading => 'Загружаем достижения…';

  @override
  String get gamificationLoadFailed =>
      'Не удалось загрузить достижения. Ранее полученные данные не изменены.';

  @override
  String get gamificationUnavailable => 'Достижения пока недоступны';

  @override
  String get gamificationLocked => 'Не открыто';

  @override
  String get gamificationUnlocked => 'Открыто';

  @override
  String gamificationUnlockedOn(String date) {
    return 'Открыто $date';
  }

  @override
  String gamificationProgress(int current, int target) {
    return '$current из $target';
  }

  @override
  String gamificationUnlockedSummary(int unlocked, int total) {
    return 'Открыто: $unlocked из $total';
  }

  @override
  String gamificationNextLevel(int points) {
    return 'До следующего уровня: $points очков';
  }

  @override
  String get gamificationMaxLevel => 'Максимальный уровень достигнут';

  @override
  String gamificationUnlockOne(String title) {
    return 'Новое достижение: $title';
  }

  @override
  String gamificationUnlockMany(int count) {
    return 'Открыто новых достижений: $count';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsTheme => 'Тема';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageKazakh => 'Қазақша';

  @override
  String get settingsSaveFailed => 'Не удалось сохранить настройку';

  @override
  String get homeworkLoadFailed => 'Не удалось загрузить карточки уроков';

  @override
  String get homeworkTitle => 'Домашнее задание';

  @override
  String get homeworkSendToday => 'Отправить в WhatsApp за сегодня';

  @override
  String get homeworkInvalidDate =>
      'Для этого дня отправка недоступна: нет корректной даты.';

  @override
  String get homeworkSessionExpired => 'Сессия истекла. Выполните вход снова.';

  @override
  String homeworkDigestSent(String date) {
    return 'Сообщение за $date отправлено в WhatsApp.';
  }

  @override
  String homeworkDigestQueued(String date) {
    return 'Отправка за $date поставлена в очередь и ещё выполняется.';
  }

  @override
  String homeworkDigestDateFailed(String date) {
    return 'Не удалось отправить сообщение за $date.';
  }

  @override
  String get homeworkWhatsappFailed =>
      'Не удалось отправить сообщение в WhatsApp.';

  @override
  String get homeworkParentPhoneRequired =>
      'Перед отправкой укажите номер родителя в профиле.';

  @override
  String get homeworkPhotoSent => 'Фото отправлено в WhatsApp.';

  @override
  String get homeworkPhotoMissing =>
      'Файл фото недоступен. Снимите фото заново.';

  @override
  String get homeworkAlreadySent =>
      'Запрос уже был отправлен ранее, статус обновлён.';

  @override
  String get homeworkSendFailed => 'Не удалось отправить домашнее задание.';

  @override
  String get homeworkPhotoSendFailed => 'Не удалось отправить фото.';

  @override
  String get homeworkCameraUnavailable =>
      'Камера недоступна. Проверьте разрешение приложения.';

  @override
  String get homeworkSubjectMissing => 'Предмет не указан';

  @override
  String get homeworkNotAssigned => 'Не задано';

  @override
  String get homeworkSendError => 'Ошибка отправки';

  @override
  String get homeworkRetakePhoto => 'Повторить фото';

  @override
  String get homeworkRetrySend => 'Повторить отправку';

  @override
  String get homeworkNoLessonsToday => 'Сегодня уроков нет';

  @override
  String homeworkLessonsToday(int count) {
    return 'Сегодня $count уроков';
  }

  @override
  String homeworkCompletedCount(int count) {
    return 'Из них $count задания выполнено';
  }

  @override
  String get homeworkShort => 'ДЗ';

  @override
  String get homeworkLessonTopic => 'Тема урока';

  @override
  String get homeworkDescriptionMissing => 'Домашнее задание не задано';

  @override
  String get homeworkTopicMissing => 'Тема урока не указана';

  @override
  String get homeworkNoLessonsDay => 'На этот день уроков нет';

  @override
  String get homeworkRestHint => 'Можно отдохнуть или выбрать другой день.';

  @override
  String get homeworkPhotoPreview => 'Предпросмотр фото';

  @override
  String homeworkSubjectLine(String subject) {
    return 'Предмет: $subject';
  }

  @override
  String get homeworkAssignment => 'Задание';

  @override
  String get homeworkTopic => 'Тема';

  @override
  String homeworkContentLine(String kind, String content) {
    return '$kind: $content';
  }

  @override
  String homeworkDateLine(String date) {
    return 'Дата: $date';
  }

  @override
  String get homeworkDateMissing => 'Не указана';

  @override
  String get gradesTitle => 'Оценки';

  @override
  String get gradesLoadFailed => 'Не удалось загрузить оценки';

  @override
  String get gradesNotLoaded => 'Оценки пока не загружены';

  @override
  String get gradesTabMain => 'Главная';

  @override
  String get gradesTabWeek => 'За неделю';

  @override
  String get gradesTabTotals => 'Итоговые';

  @override
  String get gradesLatest => 'Последние оценки';

  @override
  String get gradesAll => 'Все оценки';

  @override
  String get gradesNone => 'Оценок пока нет';

  @override
  String get gradesLatestSummative => 'Последние СОР и СОЧ';

  @override
  String get gradesAllWorks => 'Все работы';

  @override
  String get gradesNoSummative => 'СОР и СОЧ пока нет';

  @override
  String get gradesMark => 'Оценка';

  @override
  String get gradesSor => 'СОР';

  @override
  String get gradesSoch => 'СОЧ';

  @override
  String get gradesSorSoch => 'СОР/СОЧ';

  @override
  String get gradesWork => 'Работа';

  @override
  String gradesQuarter(int number) {
    return '$number четверть';
  }

  @override
  String get gradesWeekEmpty => 'За неделю оценок пока нет';

  @override
  String get gradesWeekEmptyHint =>
      'Когда появятся новые оценки, я покажу их здесь.';

  @override
  String get gradesTotalsUnavailable => 'Итоговые данные пока недоступны';

  @override
  String get gradesYearAverage => 'Средний балл за год';

  @override
  String get gradesAverage => 'Средний балл';

  @override
  String gradesForMonth(String month) {
    return 'за $month';
  }

  @override
  String get gradesKnowledgeQuality => 'Качество знаний';

  @override
  String get gradesForWeek => 'за неделю';

  @override
  String get gradesDynamics => 'Динамика';

  @override
  String get gradesSubject => 'Предмет';

  @override
  String get gradesExcellent => 'Отлично';

  @override
  String get gradesGood => 'Хорошо';

  @override
  String get gradesSatisfactoryShort => 'Удовл.';

  @override
  String get gradesAbsent => 'Не был';

  @override
  String get gradesNoMark => 'Нет оценки';

  @override
  String get gradesWeekSummary => 'Итоги недели';

  @override
  String gradesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count оценки',
      many: '$count оценок',
      few: '$count оценки',
      one: '$count оценка',
    );
    return '$_temp0';
  }

  @override
  String gradesCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'оценки',
      many: 'оценок',
      few: 'оценки',
      one: 'оценка',
    );
    return '$_temp0';
  }

  @override
  String get gradesAverageLower => 'средний балл';

  @override
  String get gradesAttendance => 'посещаемость';

  @override
  String get gradesNeedImprove => 'Нужно подтянуть';

  @override
  String get assistantTitle => 'Спросите Kundi';

  @override
  String get assistantPastChats => 'Прошлые диалоги';

  @override
  String get assistantNewChat => 'Новый диалог';

  @override
  String get assistantDeleteChat => 'Удалить диалог';

  @override
  String get assistantShowPrevious => 'Показать предыдущие сообщения';

  @override
  String get assistantQuestionHint => 'Напишите вопрос…';

  @override
  String assistantGradeClass(int grade) {
    return '$grade класс';
  }

  @override
  String get assistantShowMore => 'Показать ещё';

  @override
  String get assistantDeleteTitle => 'Удалить диалог?';

  @override
  String get assistantDeleteBody =>
      'Историю этого диалога нельзя будет восстановить.';

  @override
  String get assistantVoice => 'Голосом';

  @override
  String get assistantThinking => 'Kundi думает…';

  @override
  String get assistantEmpty =>
      'Задайте вопрос — Kundi объяснит тему, даст подсказку или проверит ваш шаг.';

  @override
  String get assistantLoadFailed => 'Не удалось загрузить диалог.';

  @override
  String get assistantHistoryRefreshFailed => 'Не удалось обновить историю';

  @override
  String get assistantSuggestionExplain => 'Объясни тему';

  @override
  String get assistantSuggestionFirstStep => 'Помоги сделать первый шаг';

  @override
  String get assistantSuggestionCheck => 'Проверь мой ответ';

  @override
  String get assistantRateLimited =>
      'Слишком много запросов. Немного подождите и попробуйте снова.';

  @override
  String get assistantUnavailable => 'Kundi пока недоступна.';

  @override
  String get assistantTemporaryFailure =>
      'Kundi временно не смогла ответить. Попробуйте ещё раз.';

  @override
  String get assistantSendFailed =>
      'Не удалось отправить сообщение. Проверьте соединение.';

  @override
  String get voiceRecognizerUnavailable =>
      'Системное распознавание речи недоступно.';

  @override
  String get voicePermissionTitle => 'Разрешить микрофон?';

  @override
  String get voicePermissionBody =>
      'Микрофон работает только во время удержания Kundi. Приложение не записывает и не хранит аудио. Системная служба устройства может обрабатывать речь локально или через своего поставщика. Распознанный текст сохраняется в истории диалога.';

  @override
  String get voiceNotNow => 'Не сейчас';

  @override
  String get voiceHoldHint => 'Теперь удерживай Kundi и говори';

  @override
  String get voiceDisabledTitle => 'Микрофон выключен';

  @override
  String get voiceDisabledBody =>
      'Разрешение можно включить в настройках приложения. Текстовый помощник продолжает работать без микрофона.';

  @override
  String get voiceOpenSettings => 'Открыть настройки';

  @override
  String get voicePreparing => 'Подготавливаю Kundi…';

  @override
  String get voiceListening => 'Я слушаю… Говори, пока удерживаешь Kundi';

  @override
  String get voiceProcessing => 'Обрабатываю речь…';

  @override
  String get voiceThinking => 'Думаю…';

  @override
  String get voiceNoSpeech => 'Не расслышала. Попробуй ещё раз.';

  @override
  String get voiceRecognitionFailed => 'Не удалось распознать речь.';

  @override
  String get voicePlaybackFailed => 'Не удалось озвучить ответ.';

  @override
  String get voiceNoMatch =>
      'Не удалось распознать речь на выбранном языке. Проверьте поддержку языка на устройстве и попробуйте ещё раз.';

  @override
  String get pullRefreshFailed =>
      'Не удалось обновить данные. Старые данные сохранены.';
}
