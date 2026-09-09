// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kazakh (`kk`).
class AppLocalizationsKk extends AppLocalizations {
  AppLocalizationsKk([String locale = 'kk']) : super(locale);

  @override
  String get appTitle => 'Kundi';

  @override
  String get commonCancel => 'Бас тарту';

  @override
  String get commonContinue => 'Жалғастыру';

  @override
  String get commonClose => 'Жабу';

  @override
  String get commonRetry => 'Қайталау';

  @override
  String get commonRefresh => 'Жаңарту';

  @override
  String get commonSend => 'Жіберу';

  @override
  String get commonDelete => 'Жою';

  @override
  String get commonNotSpecified => 'Көрсетілмеген';

  @override
  String get commonNoData => 'Дерек жоқ';

  @override
  String get commonLoading => 'Жүктелуде';

  @override
  String get commonSoon => 'Жақында';

  @override
  String get commonYear => 'Жыл';

  @override
  String get navHomework => 'ҮТ';

  @override
  String get navHome => 'Басты бет';

  @override
  String get navGrades => 'Бағалар';

  @override
  String get authLoginFailed => 'Кіру мүмкін болмады. Қайталап көріңіз.';

  @override
  String get authLoginSuccess => 'Кіру сәтті аяқталды';

  @override
  String authViaProvider(String provider) {
    return '$provider арқылы кіру';
  }

  @override
  String get authDiaryCredentials =>
      'Электрондық күнделіктің логині мен құпиясөзі';

  @override
  String get authLogin => 'Логин';

  @override
  String get authPassword => 'Құпиясөз';

  @override
  String get authContinue => 'Жалғастыру';

  @override
  String get authYourDiary => 'Сіздің электрондық күнделігіңіз';

  @override
  String get authWith => 'және ';

  @override
  String get authAiTutor => 'ЖИ-репетитор';

  @override
  String get authHello => 'Сәлем!';

  @override
  String get authIAm => 'Мен — ';

  @override
  String get authTutorSuffix => ', сіздің\nЖИ-репетиторыңызбын';

  @override
  String get authSignInPrefix => 'Өз \n';

  @override
  String get authElectronicDiary => 'электрондық күнделігіңізбен кіріңіз';

  @override
  String get authChooseService => 'Кіру сервисін таңдаңыз';

  @override
  String get authKundelik => 'Kundelik.kz арқылы кіру';

  @override
  String get authDnevnik => 'Dnevnik.ru арқылы кіру';

  @override
  String get authEduPage => 'EduPage арқылы кіру';

  @override
  String get authSecure => 'Қауіпсіз әрі сенімді';

  @override
  String get authPasswordNotStored => 'Күнделіктің құпиясөзін сақтамаймыз';

  @override
  String get homeTitle => 'Басты бет';

  @override
  String get homeGoodMorning => 'Қайырлы таң';

  @override
  String get homeGoodAfternoon => 'Қайырлы күн';

  @override
  String get homeGoodEvening => 'Қайырлы кеш';

  @override
  String get homeGoodNight => 'Қайырлы түн';

  @override
  String homeGreeting(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get homeProfileTooltip => 'Профиль';

  @override
  String get homeKundiCharacter => 'Kundi кейіпкері';

  @override
  String get homePlanAvailable => 'Бүгінгі жоспар дайын';

  @override
  String get homePlanEmpty => 'Бүгінгі жоспар әзірге бос';

  @override
  String get homeHomeworkToday => 'Бүгінгі ҮТ';

  @override
  String get homeHomeworkWeek => 'Апталық ҮТ';

  @override
  String get homeAttendance => 'Қатысу';

  @override
  String get homeAvailableData => 'Қолжетімді деректер көрсетілді';

  @override
  String get homeAskKundi => 'Kundi-ден сұраңыз...';

  @override
  String get homeAssistantDescription =>
      'Тақырыпты түсіндіріп, алғашқы қадамды жасауға көмектеседі';

  @override
  String get homeAssistantSoon => 'Жеке көмекші кейінірек қосылады';

  @override
  String get homeNearestLesson => 'Келесі сабақ';

  @override
  String get homeNoLessons => 'Сабақ жоқ';

  @override
  String get homeNoAssignments => 'Тапсырма жоқ';

  @override
  String get homeBuildingPlan => 'Бүгінгі жоспарыңды дайындап жатырмын.';

  @override
  String get homeScheduleUnavailable =>
      'Кесте уақытша қолжетімсіз. Тағы бір рет жаңартып көреміз.';

  @override
  String get homeSeeTodayPlan => 'Бүгінге не жоспарланғанын қарайық.';

  @override
  String homeTodayLessons(int count) {
    return 'Бүгін $count сабақ бар.';
  }

  @override
  String homeNearestSubject(String subject) {
    return 'Келесі сабақ — $subject.';
  }

  @override
  String homeTodayHomework(int count) {
    return 'Бүгінге $count тапсырма берілген.';
  }

  @override
  String get homeNoHomeworkToday => 'Бүгінге тапсырма жоқ';

  @override
  String homeHomeworkTodayCount(int count) {
    return 'Бүгінге $count тапсырма';
  }

  @override
  String get homeNoNewGrades => 'Жаңа баға жоқ';

  @override
  String get homeLatestResults => 'Соңғы нәтижелер';

  @override
  String get homeLatestGrades => 'Соңғы бағалар';

  @override
  String get homeKundiCelebrating => 'Жарайсың!';

  @override
  String get homeKundiCelebratingSemantic => 'Kundi жетістікке қуанады';

  @override
  String get homeKundiThinking => 'Ойланып жатырмын…';

  @override
  String get homeKundiThinkingSemantic => 'Kundi ойланып жатыр';

  @override
  String get homeKundiSpeaking => 'Жауап кейінірек осында шығады.';

  @override
  String get homeKundiSpeakingSemantic => 'Kundi жауап дайындап жатыр';

  @override
  String get homeKundiListening => 'Тыңдап тұрмын';

  @override
  String get homeKundiListeningSemantic => 'Kundi тыңдап тұр';

  @override
  String get homeKundiWarning =>
      'Назар аударуды қажет ететін нәрсені бірге тексерейік.';

  @override
  String get homeKundiWarningSemantic =>
      'Kundi маңызды нәрсені тексеруді ұсынады';

  @override
  String get homeKundiError =>
      'Бірдеңе дұрыс болмады. Кейінірек қайталап көреміз.';

  @override
  String get homeKundiErrorSemantic => 'Kundi уақытша қолжетімсіз';

  @override
  String get profileTitle => 'Профиль';

  @override
  String get profileNotLoaded => 'Профиль әлі жүктелмеді';

  @override
  String get profileLoading => 'Профиль жүктелуде...';

  @override
  String get profileLoadFailed => 'Профильді жүктеу мүмкін болмады';

  @override
  String get profileSaved => 'Профиль сақталды';

  @override
  String get profileSaveFailed =>
      'Профильді сақтау мүмкін болмады. Қайта байқап көріңіз.';

  @override
  String get profilePhotoSoon => 'Фото қосу кейінірек қолжетімді болады';

  @override
  String get profileLogoutTitle => 'Аккаунттан шығу керек пе?';

  @override
  String get profileLogoutBody =>
      'Осы құрылғыдағы ағымдағы профильден шығасыз.';

  @override
  String get profileLogout => 'Шығу';

  @override
  String get profileStudentData => 'Оқушы деректері';

  @override
  String get profileParentContacts => 'Ата-ана байланыстары';

  @override
  String get profileStudent => 'Оқушы';

  @override
  String get profileInitials => 'ПФ';

  @override
  String get profilePoints => 'Ұпай';

  @override
  String get profileStreak => 'Қатарынан күн';

  @override
  String get profileLevel => 'Деңгей';

  @override
  String get profileSchool => 'Мектеп';

  @override
  String get profileClass => 'Сынып';

  @override
  String get profileShift => 'Ауысым';

  @override
  String get profileShiftOne => '1-ауысым';

  @override
  String get profileShiftTwo => '2-ауысым';

  @override
  String get profileShiftUnknown => '—';

  @override
  String get profileTeacher => 'Сынып жетекшісі';

  @override
  String get profileContactsHelp =>
      'Қажет болғанда мектеп тез хабарласа алуы үшін ата-ананың телефон нөмірлерін қалдырыңыз.';

  @override
  String get profileParentPhoneOne => '1-ата-ананың нөмірі';

  @override
  String get profileParentPhoneOneRequired => '1-ата-ананың нөмірін енгізіңіз';

  @override
  String get profileParentPhoneTwo => '2-ата-ананың нөмірі (міндетті емес)';

  @override
  String get profilePhoneOptionalHint => 'Нөмірді енгізіңіз (міндетті емес)';

  @override
  String get profilePhoneInvalid => 'Нөмірде 10–15 цифр болуы керек';

  @override
  String get profileSaveChanges => 'Өзгерістерді сақтау';

  @override
  String get profileAchievements => 'Жетістіктер';

  @override
  String get profileAllAchievements => 'Барлық жетістік';

  @override
  String get profileAchievementExcellent => 'Үздік оқушы';

  @override
  String get profileAchievementExcellentHint => '10 үздік\nбаға';

  @override
  String get profileAchievementDiligent => 'Ынталы';

  @override
  String get profileAchievementDiligentHint => '7 күн қатарынан\nбелсенділік';

  @override
  String get profileAchievementCurious => 'Ізденімпаз';

  @override
  String get profileAchievementCuriousHint => '50 тапсырма\nорындалды';

  @override
  String get profileAchievementFirstFive => 'Алғашқы бестік';

  @override
  String get profileAchievementFirstFiveHint => '«5» деген 5\nбаға алыңыз';

  @override
  String get gamificationLoading => 'Жетістіктер жүктелуде…';

  @override
  String get gamificationLoadFailed =>
      'Жетістіктерді жүктеу мүмкін болмады. Бұрын алынған деректер өзгермеді.';

  @override
  String get gamificationUnavailable => 'Жетістіктер әзірге қолжетімсіз';

  @override
  String get gamificationLocked => 'Ашылмаған';

  @override
  String get gamificationUnlocked => 'Ашылды';

  @override
  String gamificationUnlockedOn(String date) {
    return '$date ашылды';
  }

  @override
  String gamificationProgress(int current, int target) {
    return '$current / $target';
  }

  @override
  String gamificationUnlockedSummary(int unlocked, int total) {
    return 'Ашылғаны: $unlocked / $total';
  }

  @override
  String gamificationNextLevel(int points) {
    return 'Келесі деңгейге дейін: $points ұпай';
  }

  @override
  String get gamificationMaxLevel => 'Ең жоғары деңгейге жеттіңіз';

  @override
  String gamificationUnlockOne(String title) {
    return 'Жаңа жетістік: $title';
  }

  @override
  String gamificationUnlockMany(int count) {
    return 'Жаңа жетістіктер ашылды: $count';
  }

  @override
  String get settingsTitle => 'Баптаулар';

  @override
  String get settingsTheme => 'Тақырып';

  @override
  String get settingsThemeDark => 'Қараңғы';

  @override
  String get settingsThemeLight => 'Жарық';

  @override
  String get settingsLanguage => 'Тіл';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageKazakh => 'Қазақша';

  @override
  String get settingsSaveFailed => 'Баптауды сақтау мүмкін болмады';

  @override
  String get homeworkLoadFailed => 'Сабақ карточкаларын жүктеу мүмкін болмады';

  @override
  String get homeworkTitle => 'Үй тапсырмасы';

  @override
  String get homeworkSendToday => 'Бүгінгісін WhatsApp-қа жіберу';

  @override
  String get homeworkInvalidDate =>
      'Бұл күннің дұрыс күні көрсетілмеген, сондықтан жіберу қолжетімсіз.';

  @override
  String get homeworkSessionExpired => 'Сессия аяқталды. Қайта кіріңіз.';

  @override
  String homeworkDigestSent(String date) {
    return '$date күнінің хабары WhatsApp-қа жіберілді.';
  }

  @override
  String homeworkDigestQueued(String date) {
    return '$date күнінің хабары кезекке қойылды және әлі жіберілуде.';
  }

  @override
  String homeworkDigestDateFailed(String date) {
    return '$date күнінің хабарын жіберу мүмкін болмады.';
  }

  @override
  String get homeworkWhatsappFailed =>
      'Хабарды WhatsApp-қа жіберу мүмкін болмады.';

  @override
  String get homeworkParentPhoneRequired =>
      'Жібермес бұрын профильде ата-ананың нөмірін көрсетіңіз.';

  @override
  String get homeworkPhotoSent => 'Фото WhatsApp-қа жіберілді.';

  @override
  String get homeworkPhotoMissing => 'Фото файлы қолжетімсіз. Қайта түсіріңіз.';

  @override
  String get homeworkAlreadySent => 'Сұрау бұрын жіберілген, күйі жаңартылды.';

  @override
  String get homeworkSendFailed => 'Үй тапсырмасын жіберу мүмкін болмады.';

  @override
  String get homeworkPhotoSendFailed => 'Фотоны жіберу мүмкін болмады.';

  @override
  String get homeworkCameraUnavailable =>
      'Камера қолжетімсіз. Қолданба рұқсатын тексеріңіз.';

  @override
  String get homeworkSubjectMissing => 'Пән көрсетілмеген';

  @override
  String get homeworkNotAssigned => 'Берілмеген';

  @override
  String get homeworkSendError => 'Жіберу қатесі';

  @override
  String get homeworkRetakePhoto => 'Фотоны қайта түсіру';

  @override
  String get homeworkRetrySend => 'Қайта жіберу';

  @override
  String get homeworkNoLessonsToday => 'Бүгін сабақ жоқ';

  @override
  String homeworkLessonsToday(int count) {
    return 'Бүгін $count сабақ';
  }

  @override
  String homeworkCompletedCount(int count) {
    return 'Оның $count тапсырмасы орындалды';
  }

  @override
  String get homeworkShort => 'ҮТ';

  @override
  String get homeworkLessonTopic => 'Сабақ тақырыбы';

  @override
  String get homeworkDescriptionMissing => 'Үй тапсырмасы берілмеген';

  @override
  String get homeworkTopicMissing => 'Сабақ тақырыбы көрсетілмеген';

  @override
  String get homeworkNoLessonsDay => 'Бұл күні сабақ жоқ';

  @override
  String get homeworkRestHint => 'Демалуға немесе басқа күнді таңдауға болады.';

  @override
  String get homeworkPhotoPreview => 'Фотоны алдын ала қарау';

  @override
  String homeworkSubjectLine(String subject) {
    return 'Пән: $subject';
  }

  @override
  String get homeworkAssignment => 'Тапсырма';

  @override
  String get homeworkTopic => 'Тақырып';

  @override
  String homeworkContentLine(String kind, String content) {
    return '$kind: $content';
  }

  @override
  String homeworkDateLine(String date) {
    return 'Күні: $date';
  }

  @override
  String get homeworkDateMissing => 'Көрсетілмеген';

  @override
  String get gradesTitle => 'Бағалар';

  @override
  String get gradesLoadFailed => 'Бағаларды жүктеу мүмкін болмады';

  @override
  String get gradesNotLoaded => 'Бағалар әлі жүктелмеді';

  @override
  String get gradesTabMain => 'Басты бет';

  @override
  String get gradesTabWeek => 'Апта бойынша';

  @override
  String get gradesTabTotals => 'Қорытынды';

  @override
  String get gradesLatest => 'Соңғы бағалар';

  @override
  String get gradesAll => 'Барлық баға';

  @override
  String get gradesNone => 'Әзірге баға жоқ';

  @override
  String get gradesLatestSummative => 'Соңғы БЖБ және ТЖБ';

  @override
  String get gradesAllWorks => 'Барлық жұмыс';

  @override
  String get gradesNoSummative => 'БЖБ және ТЖБ әзірге жоқ';

  @override
  String get gradesMark => 'Баға';

  @override
  String get gradesSor => 'БЖБ';

  @override
  String get gradesSoch => 'ТЖБ';

  @override
  String get gradesSorSoch => 'БЖБ/ТЖБ';

  @override
  String get gradesWork => 'Жұмыс';

  @override
  String gradesQuarter(int number) {
    return '$number-тоқсан';
  }

  @override
  String get gradesWeekEmpty => 'Апта ішінде баға жоқ';

  @override
  String get gradesWeekEmptyHint =>
      'Жаңа бағалар шыққанда, оларды осы жерден көрсетемін.';

  @override
  String get gradesTotalsUnavailable => 'Қорытынды деректер әзірге қолжетімсіз';

  @override
  String get gradesYearAverage => 'Жылдық орташа балл';

  @override
  String get gradesAverage => 'Орташа балл';

  @override
  String gradesForMonth(String month) {
    return '$month айы бойынша';
  }

  @override
  String get gradesKnowledgeQuality => 'Білім сапасы';

  @override
  String get gradesForWeek => 'апта бойынша';

  @override
  String get gradesDynamics => 'Өзгеріс';

  @override
  String get gradesSubject => 'Пән';

  @override
  String get gradesExcellent => 'Өте жақсы';

  @override
  String get gradesGood => 'Жақсы';

  @override
  String get gradesSatisfactoryShort => 'Қанағат.';

  @override
  String get gradesAbsent => 'Қатыспады';

  @override
  String get gradesNoMark => 'Баға жоқ';

  @override
  String get gradesWeekSummary => 'Апта қорытындысы';

  @override
  String gradesCount(int count) {
    return '$count баға';
  }

  @override
  String gradesCountLabel(int count) {
    return 'баға';
  }

  @override
  String get gradesAverageLower => 'орташа балл';

  @override
  String get gradesAttendance => 'қатысу';

  @override
  String get gradesNeedImprove => 'Жақсарту керек';

  @override
  String get assistantTitle => 'Kundi-ден сұраңыз';

  @override
  String get assistantSubtitle => 'Оқу бойынша көмекші';

  @override
  String get assistantPastChats => 'Алдыңғы диалогтар';

  @override
  String get assistantNewChat => 'Жаңа диалог';

  @override
  String get assistantDeleteChat => 'Диалогты жою';

  @override
  String get assistantShowPrevious => 'Алдыңғы хабарларды көрсету';

  @override
  String get assistantQuestionHint => 'Сұрағыңызды жазыңыз…';

  @override
  String assistantGradeClass(int grade) {
    return '$grade-сынып';
  }

  @override
  String get assistantShowMore => 'Тағы көрсету';

  @override
  String get assistantDeleteTitle => 'Диалог жойылсын ба?';

  @override
  String get assistantDeleteBody =>
      'Бұл диалогтың тарихын қалпына келтіру мүмкін болмайды.';

  @override
  String get assistantVoice => 'Дауыспен';

  @override
  String get assistantThinking => 'Kundi ойланып жатыр…';

  @override
  String get assistantEmpty =>
      'Сұрақ қойыңыз — Kundi тақырыпты түсіндіреді, кеңес береді немесе қадамыңызды тексереді.';

  @override
  String get assistantLoadFailed => 'Диалогты жүктеу мүмкін болмады.';

  @override
  String get assistantHistoryRefreshFailed => 'Тарихты жаңарту мүмкін болмады';

  @override
  String get assistantSuggestionExplain => 'Тақырыпты түсіндір';

  @override
  String get assistantSuggestionFirstStep => 'Алғашқы қадамды жасауға көмектес';

  @override
  String get assistantSuggestionCheck => 'Жауабымды тексер';

  @override
  String get assistantRateLimited =>
      'Сұрау тым көп. Сәл күтіп, қайталап көріңіз.';

  @override
  String get assistantUnavailable => 'Kundi әзірге қолжетімсіз.';

  @override
  String get assistantTemporaryFailure =>
      'Kundi уақытша жауап бере алмады. Қайталап көріңіз.';

  @override
  String get assistantSendFailed =>
      'Хабарды жіберу мүмкін болмады. Байланысты тексеріңіз.';

  @override
  String get voiceRecognizerUnavailable => 'Жүйелік сөйлеуді тану қолжетімсіз.';

  @override
  String get voicePermissionTitle => 'Микрофонға рұқсат берілсін бе?';

  @override
  String get voicePermissionBody =>
      'Микрофон Kundi-ді басып тұрған кезде ғана жұмыс істейді. Қолданба аудионы жазбайды және сақтамайды. Құрылғының жүйелік қызметі сөйлеуді құрылғыда немесе өз провайдері арқылы өңдеуі мүмкін. Танылған мәтін диалог тарихында сақталады.';

  @override
  String get voiceNotNow => 'Қазір емес';

  @override
  String get voiceHoldHint => 'Енді Kundi-ді басып тұрып сөйлеңіз';

  @override
  String get voiceDisabledTitle => 'Микрофон өшірулі';

  @override
  String get voiceDisabledBody =>
      'Рұқсатты қолданба баптауларынан қосуға болады. Мәтіндік көмекші микрофонсыз да жұмыс істейді.';

  @override
  String get voiceOpenSettings => 'Баптауларды ашу';

  @override
  String get voicePreparing => 'Kundi дайындалуда…';

  @override
  String get voiceListening => 'Тыңдап тұрмын… Kundi-ді басып тұрып сөйлеңіз';

  @override
  String get voiceProcessing => 'Сөйлеу өңделуде…';

  @override
  String get voiceThinking => 'Ойланып жатырмын…';

  @override
  String get voiceNoSpeech => 'Дауыс естілмеді. Қайталап көріңіз.';

  @override
  String get voiceRecognitionFailed => 'Сөйлеуді тану мүмкін болмады.';

  @override
  String get voicePlaybackFailed => 'Жауапты дыбыстау мүмкін болмады.';

  @override
  String get voiceNoMatch =>
      'Таңдалған тілдегі сөзді тану мүмкін болмады. Құрылғының осы тілді қолдайтынын тексеріп, қайталап көріңіз.';

  @override
  String get pullRefreshFailed =>
      'Деректерді жаңарту мүмкін болмады. Бұрынғы деректер сақталды.';
}
