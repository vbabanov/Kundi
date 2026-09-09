import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_kk.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('kk'),
    Locale('ru')
  ];

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'Kundi'**
  String get appTitle;

  /// No description provided for @commonCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get commonCancel;

  /// No description provided for @commonContinue.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get commonContinue;

  /// No description provided for @commonClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get commonRetry;

  /// No description provided for @commonRefresh.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get commonRefresh;

  /// No description provided for @commonSend.
  ///
  /// In ru, this message translates to:
  /// **'Отправить'**
  String get commonSend;

  /// No description provided for @commonDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get commonDelete;

  /// No description provided for @commonNotSpecified.
  ///
  /// In ru, this message translates to:
  /// **'Не указано'**
  String get commonNotSpecified;

  /// No description provided for @commonNoData.
  ///
  /// In ru, this message translates to:
  /// **'Нет данных'**
  String get commonNoData;

  /// No description provided for @commonLoading.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка'**
  String get commonLoading;

  /// No description provided for @commonSoon.
  ///
  /// In ru, this message translates to:
  /// **'Скоро'**
  String get commonSoon;

  /// No description provided for @commonYear.
  ///
  /// In ru, this message translates to:
  /// **'Год'**
  String get commonYear;

  /// No description provided for @navHomework.
  ///
  /// In ru, this message translates to:
  /// **'ДЗ'**
  String get navHomework;

  /// No description provided for @navHome.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get navHome;

  /// No description provided for @navGrades.
  ///
  /// In ru, this message translates to:
  /// **'Оценки'**
  String get navGrades;

  /// No description provided for @authLoginFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось войти. Попробуйте ещё раз.'**
  String get authLoginFailed;

  /// No description provided for @authLoginSuccess.
  ///
  /// In ru, this message translates to:
  /// **'Вход выполнен'**
  String get authLoginSuccess;

  /// No description provided for @authViaProvider.
  ///
  /// In ru, this message translates to:
  /// **'Вход через {provider}'**
  String authViaProvider(String provider);

  /// No description provided for @authDiaryCredentials.
  ///
  /// In ru, this message translates to:
  /// **'Логин и пароль от электронного дневника'**
  String get authDiaryCredentials;

  /// No description provided for @authLogin.
  ///
  /// In ru, this message translates to:
  /// **'Логин'**
  String get authLogin;

  /// No description provided for @authPassword.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get authPassword;

  /// No description provided for @authContinue.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get authContinue;

  /// No description provided for @authYourDiary.
  ///
  /// In ru, this message translates to:
  /// **'Ваш электронный дневник'**
  String get authYourDiary;

  /// No description provided for @authWith.
  ///
  /// In ru, this message translates to:
  /// **'с '**
  String get authWith;

  /// No description provided for @authAiTutor.
  ///
  /// In ru, this message translates to:
  /// **'ИИ-репетитором'**
  String get authAiTutor;

  /// No description provided for @authHello.
  ///
  /// In ru, this message translates to:
  /// **'Привет!'**
  String get authHello;

  /// No description provided for @authIAm.
  ///
  /// In ru, this message translates to:
  /// **'Я '**
  String get authIAm;

  /// No description provided for @authTutorSuffix.
  ///
  /// In ru, this message translates to:
  /// **', ваш\nИИ-репетитор'**
  String get authTutorSuffix;

  /// No description provided for @authSignInPrefix.
  ///
  /// In ru, this message translates to:
  /// **'Войдите через ваш\n'**
  String get authSignInPrefix;

  /// No description provided for @authElectronicDiary.
  ///
  /// In ru, this message translates to:
  /// **'электронный дневник'**
  String get authElectronicDiary;

  /// No description provided for @authChooseService.
  ///
  /// In ru, this message translates to:
  /// **'Выберите сервис для входа'**
  String get authChooseService;

  /// No description provided for @authKundelik.
  ///
  /// In ru, this message translates to:
  /// **'Войти через Kundelik.kz'**
  String get authKundelik;

  /// No description provided for @authDnevnik.
  ///
  /// In ru, this message translates to:
  /// **'Войти через Dnevnik.ru'**
  String get authDnevnik;

  /// No description provided for @authEduPage.
  ///
  /// In ru, this message translates to:
  /// **'Войти через EduPage'**
  String get authEduPage;

  /// No description provided for @authSecure.
  ///
  /// In ru, this message translates to:
  /// **'Безопасно и надёжно'**
  String get authSecure;

  /// No description provided for @authPasswordNotStored.
  ///
  /// In ru, this message translates to:
  /// **'Мы не храним пароль от дневника'**
  String get authPasswordNotStored;

  /// No description provided for @homeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get homeTitle;

  /// No description provided for @homeGoodMorning.
  ///
  /// In ru, this message translates to:
  /// **'Доброе утро'**
  String get homeGoodMorning;

  /// No description provided for @homeGoodAfternoon.
  ///
  /// In ru, this message translates to:
  /// **'Добрый день'**
  String get homeGoodAfternoon;

  /// No description provided for @homeGoodEvening.
  ///
  /// In ru, this message translates to:
  /// **'Добрый вечер'**
  String get homeGoodEvening;

  /// No description provided for @homeGoodNight.
  ///
  /// In ru, this message translates to:
  /// **'Доброй ночи'**
  String get homeGoodNight;

  /// No description provided for @homeGreeting.
  ///
  /// In ru, this message translates to:
  /// **'{greeting}, {name}'**
  String homeGreeting(String greeting, String name);

  /// No description provided for @homeProfileTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get homeProfileTooltip;

  /// No description provided for @homeKundiCharacter.
  ///
  /// In ru, this message translates to:
  /// **'Персонаж Kundi'**
  String get homeKundiCharacter;

  /// No description provided for @homePlanAvailable.
  ///
  /// In ru, this message translates to:
  /// **'План на сегодня доступен'**
  String get homePlanAvailable;

  /// No description provided for @homePlanEmpty.
  ///
  /// In ru, this message translates to:
  /// **'План на сегодня пока пуст'**
  String get homePlanEmpty;

  /// No description provided for @homeHomeworkToday.
  ///
  /// In ru, this message translates to:
  /// **'ДЗ сегодня'**
  String get homeHomeworkToday;

  /// No description provided for @homeHomeworkWeek.
  ///
  /// In ru, this message translates to:
  /// **'ДЗ за неделю'**
  String get homeHomeworkWeek;

  /// No description provided for @homeAttendance.
  ///
  /// In ru, this message translates to:
  /// **'Посещаемость'**
  String get homeAttendance;

  /// No description provided for @homeAvailableData.
  ///
  /// In ru, this message translates to:
  /// **'Показываем доступные данные'**
  String get homeAvailableData;

  /// No description provided for @homeAskKundi.
  ///
  /// In ru, this message translates to:
  /// **'Спросите Kundi...'**
  String get homeAskKundi;

  /// No description provided for @homeAssistantDescription.
  ///
  /// In ru, this message translates to:
  /// **'Объяснит тему и поможет сделать первый шаг'**
  String get homeAssistantDescription;

  /// No description provided for @homeAssistantSoon.
  ///
  /// In ru, this message translates to:
  /// **'Персональный помощник появится позже'**
  String get homeAssistantSoon;

  /// No description provided for @homeNearestLesson.
  ///
  /// In ru, this message translates to:
  /// **'Ближайший урок'**
  String get homeNearestLesson;

  /// No description provided for @homeNoLessons.
  ///
  /// In ru, this message translates to:
  /// **'Нет уроков'**
  String get homeNoLessons;

  /// No description provided for @homeNoAssignments.
  ///
  /// In ru, this message translates to:
  /// **'Нет заданий'**
  String get homeNoAssignments;

  /// No description provided for @homeBuildingPlan.
  ///
  /// In ru, this message translates to:
  /// **'Собираю твой план на сегодня.'**
  String get homeBuildingPlan;

  /// No description provided for @homeScheduleUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Расписание временно недоступно. Попробуем обновить ещё раз.'**
  String get homeScheduleUnavailable;

  /// No description provided for @homeSeeTodayPlan.
  ///
  /// In ru, this message translates to:
  /// **'Давай посмотрим, что запланировано на сегодня.'**
  String get homeSeeTodayPlan;

  /// No description provided for @homeTodayLessons.
  ///
  /// In ru, this message translates to:
  /// **'Сегодня у тебя {count, plural, one{{count} урок} few{{count} урока} many{{count} уроков} other{{count} урока}}.'**
  String homeTodayLessons(int count);

  /// No description provided for @homeNearestSubject.
  ///
  /// In ru, this message translates to:
  /// **'Ближайший — {subject}.'**
  String homeNearestSubject(String subject);

  /// No description provided for @homeTodayHomework.
  ///
  /// In ru, this message translates to:
  /// **'На сегодня {count, plural, one{{count} задание} few{{count} задания} many{{count} заданий} other{{count} задания}}.'**
  String homeTodayHomework(int count);

  /// No description provided for @homeNoHomeworkToday.
  ///
  /// In ru, this message translates to:
  /// **'Заданий на сегодня нет'**
  String get homeNoHomeworkToday;

  /// No description provided for @homeHomeworkTodayCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} задание} few{{count} задания} many{{count} заданий} other{{count} задания}} на сегодня'**
  String homeHomeworkTodayCount(int count);

  /// No description provided for @homeNoNewGrades.
  ///
  /// In ru, this message translates to:
  /// **'Новых оценок нет'**
  String get homeNoNewGrades;

  /// No description provided for @homeLatestResults.
  ///
  /// In ru, this message translates to:
  /// **'Последние результаты'**
  String get homeLatestResults;

  /// No description provided for @homeLatestGrades.
  ///
  /// In ru, this message translates to:
  /// **'Последние оценки'**
  String get homeLatestGrades;

  /// No description provided for @homeKundiCelebrating.
  ///
  /// In ru, this message translates to:
  /// **'Отличная работа!'**
  String get homeKundiCelebrating;

  /// No description provided for @homeKundiCelebratingSemantic.
  ///
  /// In ru, this message translates to:
  /// **'Kundi радуется успеху'**
  String get homeKundiCelebratingSemantic;

  /// No description provided for @homeKundiThinking.
  ///
  /// In ru, this message translates to:
  /// **'Думаю…'**
  String get homeKundiThinking;

  /// No description provided for @homeKundiThinkingSemantic.
  ///
  /// In ru, this message translates to:
  /// **'Kundi думает'**
  String get homeKundiThinkingSemantic;

  /// No description provided for @homeKundiSpeaking.
  ///
  /// In ru, this message translates to:
  /// **'Ответ появится здесь позже.'**
  String get homeKundiSpeaking;

  /// No description provided for @homeKundiSpeakingSemantic.
  ///
  /// In ru, this message translates to:
  /// **'Kundi готовит ответ'**
  String get homeKundiSpeakingSemantic;

  /// No description provided for @homeKundiListening.
  ///
  /// In ru, this message translates to:
  /// **'Я слушаю'**
  String get homeKundiListening;

  /// No description provided for @homeKundiListeningSemantic.
  ///
  /// In ru, this message translates to:
  /// **'Kundi слушает'**
  String get homeKundiListeningSemantic;

  /// No description provided for @homeKundiWarning.
  ///
  /// In ru, this message translates to:
  /// **'Давай спокойно проверим, что требует внимания.'**
  String get homeKundiWarning;

  /// No description provided for @homeKundiWarningSemantic.
  ///
  /// In ru, this message translates to:
  /// **'Kundi предлагает проверить важное'**
  String get homeKundiWarningSemantic;

  /// No description provided for @homeKundiError.
  ///
  /// In ru, this message translates to:
  /// **'Что-то пошло не так. Попробуем ещё раз позже.'**
  String get homeKundiError;

  /// No description provided for @homeKundiErrorSemantic.
  ///
  /// In ru, this message translates to:
  /// **'Kundi временно недоступен'**
  String get homeKundiErrorSemantic;

  /// No description provided for @profileTitle.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get profileTitle;

  /// No description provided for @profileNotLoaded.
  ///
  /// In ru, this message translates to:
  /// **'Профиль ещё не загружен'**
  String get profileNotLoaded;

  /// No description provided for @profileLoading.
  ///
  /// In ru, this message translates to:
  /// **'Загружаю профиль...'**
  String get profileLoading;

  /// No description provided for @profileLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить профиль'**
  String get profileLoadFailed;

  /// No description provided for @profileSaved.
  ///
  /// In ru, this message translates to:
  /// **'Профиль сохранён'**
  String get profileSaved;

  /// No description provided for @profileSaveFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить профиль. Попробуйте ещё раз.'**
  String get profileSaveFailed;

  /// No description provided for @profilePhotoSoon.
  ///
  /// In ru, this message translates to:
  /// **'Добавление фото появится позже'**
  String get profilePhotoSoon;

  /// No description provided for @profileLogoutTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из аккаунта?'**
  String get profileLogoutTitle;

  /// No description provided for @profileLogoutBody.
  ///
  /// In ru, this message translates to:
  /// **'Вы выйдете из текущего профиля на этом устройстве.'**
  String get profileLogoutBody;

  /// No description provided for @profileLogout.
  ///
  /// In ru, this message translates to:
  /// **'Выйти'**
  String get profileLogout;

  /// No description provided for @profileStudentData.
  ///
  /// In ru, this message translates to:
  /// **'Данные ученика'**
  String get profileStudentData;

  /// No description provided for @profileParentContacts.
  ///
  /// In ru, this message translates to:
  /// **'Контакты родителей'**
  String get profileParentContacts;

  /// No description provided for @profileStudent.
  ///
  /// In ru, this message translates to:
  /// **'Ученик'**
  String get profileStudent;

  /// No description provided for @profileInitials.
  ///
  /// In ru, this message translates to:
  /// **'ПР'**
  String get profileInitials;

  /// No description provided for @profilePoints.
  ///
  /// In ru, this message translates to:
  /// **'Баллы'**
  String get profilePoints;

  /// No description provided for @profileStreak.
  ///
  /// In ru, this message translates to:
  /// **'Дней подряд'**
  String get profileStreak;

  /// No description provided for @profileLevel.
  ///
  /// In ru, this message translates to:
  /// **'Уровень'**
  String get profileLevel;

  /// No description provided for @profileSchool.
  ///
  /// In ru, this message translates to:
  /// **'Школа'**
  String get profileSchool;

  /// No description provided for @profileClass.
  ///
  /// In ru, this message translates to:
  /// **'Класс'**
  String get profileClass;

  /// No description provided for @profileShift.
  ///
  /// In ru, this message translates to:
  /// **'Смена'**
  String get profileShift;

  /// No description provided for @profileShiftOne.
  ///
  /// In ru, this message translates to:
  /// **'1 смена'**
  String get profileShiftOne;

  /// No description provided for @profileShiftTwo.
  ///
  /// In ru, this message translates to:
  /// **'2 смена'**
  String get profileShiftTwo;

  /// No description provided for @profileShiftUnknown.
  ///
  /// In ru, this message translates to:
  /// **'—'**
  String get profileShiftUnknown;

  /// No description provided for @profileTeacher.
  ///
  /// In ru, this message translates to:
  /// **'Классный руководитель'**
  String get profileTeacher;

  /// No description provided for @profileContactsHelp.
  ///
  /// In ru, this message translates to:
  /// **'Оставьте номера родителей, чтобы школа могла быстро связаться при необходимости.'**
  String get profileContactsHelp;

  /// No description provided for @profileParentPhoneOne.
  ///
  /// In ru, this message translates to:
  /// **'Номер родителя 1'**
  String get profileParentPhoneOne;

  /// No description provided for @profileParentPhoneOneRequired.
  ///
  /// In ru, this message translates to:
  /// **'Введите номер родителя 1'**
  String get profileParentPhoneOneRequired;

  /// No description provided for @profileParentPhoneTwo.
  ///
  /// In ru, this message translates to:
  /// **'Номер родителя 2 (необязательно)'**
  String get profileParentPhoneTwo;

  /// No description provided for @profilePhoneOptionalHint.
  ///
  /// In ru, this message translates to:
  /// **'Введите номер (необязательно)'**
  String get profilePhoneOptionalHint;

  /// No description provided for @profilePhoneInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Номер должен содержать от 10 до 15 цифр'**
  String get profilePhoneInvalid;

  /// No description provided for @profileSaveChanges.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить изменения'**
  String get profileSaveChanges;

  /// No description provided for @profileAchievements.
  ///
  /// In ru, this message translates to:
  /// **'Достижения'**
  String get profileAchievements;

  /// No description provided for @profileAllAchievements.
  ///
  /// In ru, this message translates to:
  /// **'Все достижения'**
  String get profileAllAchievements;

  /// No description provided for @profileAchievementExcellent.
  ///
  /// In ru, this message translates to:
  /// **'Отличник'**
  String get profileAchievementExcellent;

  /// No description provided for @profileAchievementExcellentHint.
  ///
  /// In ru, this message translates to:
  /// **'10 отличных\nоценок'**
  String get profileAchievementExcellentHint;

  /// No description provided for @profileAchievementDiligent.
  ///
  /// In ru, this message translates to:
  /// **'Старательный'**
  String get profileAchievementDiligent;

  /// No description provided for @profileAchievementDiligentHint.
  ///
  /// In ru, this message translates to:
  /// **'7 дней подряд\nактивности'**
  String get profileAchievementDiligentHint;

  /// No description provided for @profileAchievementCurious.
  ///
  /// In ru, this message translates to:
  /// **'Любознательный'**
  String get profileAchievementCurious;

  /// No description provided for @profileAchievementCuriousHint.
  ///
  /// In ru, this message translates to:
  /// **'50 заданий\nвыполнено'**
  String get profileAchievementCuriousHint;

  /// No description provided for @profileAchievementFirstFive.
  ///
  /// In ru, this message translates to:
  /// **'Первая пятёрка'**
  String get profileAchievementFirstFive;

  /// No description provided for @profileAchievementFirstFiveHint.
  ///
  /// In ru, this message translates to:
  /// **'Получите 5 оценок\n«5»'**
  String get profileAchievementFirstFiveHint;

  /// No description provided for @gamificationLoading.
  ///
  /// In ru, this message translates to:
  /// **'Загружаем достижения…'**
  String get gamificationLoading;

  /// No description provided for @gamificationLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить достижения. Ранее полученные данные не изменены.'**
  String get gamificationLoadFailed;

  /// No description provided for @gamificationUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Достижения пока недоступны'**
  String get gamificationUnavailable;

  /// No description provided for @gamificationLocked.
  ///
  /// In ru, this message translates to:
  /// **'Не открыто'**
  String get gamificationLocked;

  /// No description provided for @gamificationUnlocked.
  ///
  /// In ru, this message translates to:
  /// **'Открыто'**
  String get gamificationUnlocked;

  /// No description provided for @gamificationUnlockedOn.
  ///
  /// In ru, this message translates to:
  /// **'Открыто {date}'**
  String gamificationUnlockedOn(String date);

  /// No description provided for @gamificationProgress.
  ///
  /// In ru, this message translates to:
  /// **'{current} из {target}'**
  String gamificationProgress(int current, int target);

  /// No description provided for @gamificationUnlockedSummary.
  ///
  /// In ru, this message translates to:
  /// **'Открыто: {unlocked} из {total}'**
  String gamificationUnlockedSummary(int unlocked, int total);

  /// No description provided for @gamificationNextLevel.
  ///
  /// In ru, this message translates to:
  /// **'До следующего уровня: {points} очков'**
  String gamificationNextLevel(int points);

  /// No description provided for @gamificationMaxLevel.
  ///
  /// In ru, this message translates to:
  /// **'Максимальный уровень достигнут'**
  String get gamificationMaxLevel;

  /// No description provided for @gamificationUnlockOne.
  ///
  /// In ru, this message translates to:
  /// **'Новое достижение: {title}'**
  String gamificationUnlockOne(String title);

  /// No description provided for @gamificationUnlockMany.
  ///
  /// In ru, this message translates to:
  /// **'Открыто новых достижений: {count}'**
  String gamificationUnlockMany(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @settingsTheme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get settingsTheme;

  /// No description provided for @settingsThemeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get settingsThemeLight;

  /// No description provided for @settingsLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageRussian.
  ///
  /// In ru, this message translates to:
  /// **'Русский'**
  String get settingsLanguageRussian;

  /// No description provided for @settingsLanguageKazakh.
  ///
  /// In ru, this message translates to:
  /// **'Қазақша'**
  String get settingsLanguageKazakh;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить настройку'**
  String get settingsSaveFailed;

  /// No description provided for @homeworkLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить карточки уроков'**
  String get homeworkLoadFailed;

  /// No description provided for @homeworkTitle.
  ///
  /// In ru, this message translates to:
  /// **'Домашнее задание'**
  String get homeworkTitle;

  /// No description provided for @homeworkSendToday.
  ///
  /// In ru, this message translates to:
  /// **'Отправить в WhatsApp за сегодня'**
  String get homeworkSendToday;

  /// No description provided for @homeworkInvalidDate.
  ///
  /// In ru, this message translates to:
  /// **'Для этого дня отправка недоступна: нет корректной даты.'**
  String get homeworkInvalidDate;

  /// No description provided for @homeworkSessionExpired.
  ///
  /// In ru, this message translates to:
  /// **'Сессия истекла. Выполните вход снова.'**
  String get homeworkSessionExpired;

  /// No description provided for @homeworkDigestSent.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение за {date} отправлено в WhatsApp.'**
  String homeworkDigestSent(String date);

  /// No description provided for @homeworkDigestQueued.
  ///
  /// In ru, this message translates to:
  /// **'Отправка за {date} поставлена в очередь и ещё выполняется.'**
  String homeworkDigestQueued(String date);

  /// No description provided for @homeworkDigestDateFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отправить сообщение за {date}.'**
  String homeworkDigestDateFailed(String date);

  /// No description provided for @homeworkWhatsappFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отправить сообщение в WhatsApp.'**
  String get homeworkWhatsappFailed;

  /// No description provided for @homeworkParentPhoneRequired.
  ///
  /// In ru, this message translates to:
  /// **'Перед отправкой укажите номер родителя в профиле.'**
  String get homeworkParentPhoneRequired;

  /// No description provided for @homeworkPhotoSent.
  ///
  /// In ru, this message translates to:
  /// **'Фото отправлено в WhatsApp.'**
  String get homeworkPhotoSent;

  /// No description provided for @homeworkPhotoMissing.
  ///
  /// In ru, this message translates to:
  /// **'Файл фото недоступен. Снимите фото заново.'**
  String get homeworkPhotoMissing;

  /// No description provided for @homeworkAlreadySent.
  ///
  /// In ru, this message translates to:
  /// **'Запрос уже был отправлен ранее, статус обновлён.'**
  String get homeworkAlreadySent;

  /// No description provided for @homeworkSendFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отправить домашнее задание.'**
  String get homeworkSendFailed;

  /// No description provided for @homeworkPhotoSendFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отправить фото.'**
  String get homeworkPhotoSendFailed;

  /// No description provided for @homeworkCameraUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Камера недоступна. Проверьте разрешение приложения.'**
  String get homeworkCameraUnavailable;

  /// No description provided for @homeworkSubjectMissing.
  ///
  /// In ru, this message translates to:
  /// **'Предмет не указан'**
  String get homeworkSubjectMissing;

  /// No description provided for @homeworkNotAssigned.
  ///
  /// In ru, this message translates to:
  /// **'Не задано'**
  String get homeworkNotAssigned;

  /// No description provided for @homeworkSendError.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка отправки'**
  String get homeworkSendError;

  /// No description provided for @homeworkRetakePhoto.
  ///
  /// In ru, this message translates to:
  /// **'Повторить фото'**
  String get homeworkRetakePhoto;

  /// No description provided for @homeworkRetrySend.
  ///
  /// In ru, this message translates to:
  /// **'Повторить отправку'**
  String get homeworkRetrySend;

  /// No description provided for @homeworkNoLessonsToday.
  ///
  /// In ru, this message translates to:
  /// **'Сегодня уроков нет'**
  String get homeworkNoLessonsToday;

  /// No description provided for @homeworkLessonsToday.
  ///
  /// In ru, this message translates to:
  /// **'Сегодня {count} уроков'**
  String homeworkLessonsToday(int count);

  /// No description provided for @homeworkCompletedCount.
  ///
  /// In ru, this message translates to:
  /// **'Из них {count} задания выполнено'**
  String homeworkCompletedCount(int count);

  /// No description provided for @homeworkShort.
  ///
  /// In ru, this message translates to:
  /// **'ДЗ'**
  String get homeworkShort;

  /// No description provided for @homeworkLessonTopic.
  ///
  /// In ru, this message translates to:
  /// **'Тема урока'**
  String get homeworkLessonTopic;

  /// No description provided for @homeworkDescriptionMissing.
  ///
  /// In ru, this message translates to:
  /// **'Домашнее задание не задано'**
  String get homeworkDescriptionMissing;

  /// No description provided for @homeworkTopicMissing.
  ///
  /// In ru, this message translates to:
  /// **'Тема урока не указана'**
  String get homeworkTopicMissing;

  /// No description provided for @homeworkNoLessonsDay.
  ///
  /// In ru, this message translates to:
  /// **'На этот день уроков нет'**
  String get homeworkNoLessonsDay;

  /// No description provided for @homeworkRestHint.
  ///
  /// In ru, this message translates to:
  /// **'Можно отдохнуть или выбрать другой день.'**
  String get homeworkRestHint;

  /// No description provided for @homeworkPhotoPreview.
  ///
  /// In ru, this message translates to:
  /// **'Предпросмотр фото'**
  String get homeworkPhotoPreview;

  /// No description provided for @homeworkSubjectLine.
  ///
  /// In ru, this message translates to:
  /// **'Предмет: {subject}'**
  String homeworkSubjectLine(String subject);

  /// No description provided for @homeworkAssignment.
  ///
  /// In ru, this message translates to:
  /// **'Задание'**
  String get homeworkAssignment;

  /// No description provided for @homeworkTopic.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get homeworkTopic;

  /// No description provided for @homeworkContentLine.
  ///
  /// In ru, this message translates to:
  /// **'{kind}: {content}'**
  String homeworkContentLine(String kind, String content);

  /// No description provided for @homeworkDateLine.
  ///
  /// In ru, this message translates to:
  /// **'Дата: {date}'**
  String homeworkDateLine(String date);

  /// No description provided for @homeworkDateMissing.
  ///
  /// In ru, this message translates to:
  /// **'Не указана'**
  String get homeworkDateMissing;

  /// No description provided for @gradesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Оценки'**
  String get gradesTitle;

  /// No description provided for @gradesLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить оценки'**
  String get gradesLoadFailed;

  /// No description provided for @gradesNotLoaded.
  ///
  /// In ru, this message translates to:
  /// **'Оценки пока не загружены'**
  String get gradesNotLoaded;

  /// No description provided for @gradesTabMain.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get gradesTabMain;

  /// No description provided for @gradesTabWeek.
  ///
  /// In ru, this message translates to:
  /// **'За неделю'**
  String get gradesTabWeek;

  /// No description provided for @gradesTabTotals.
  ///
  /// In ru, this message translates to:
  /// **'Итоговые'**
  String get gradesTabTotals;

  /// No description provided for @gradesLatest.
  ///
  /// In ru, this message translates to:
  /// **'Последние оценки'**
  String get gradesLatest;

  /// No description provided for @gradesAll.
  ///
  /// In ru, this message translates to:
  /// **'Все оценки'**
  String get gradesAll;

  /// No description provided for @gradesNone.
  ///
  /// In ru, this message translates to:
  /// **'Оценок пока нет'**
  String get gradesNone;

  /// No description provided for @gradesLatestSummative.
  ///
  /// In ru, this message translates to:
  /// **'Последние СОР и СОЧ'**
  String get gradesLatestSummative;

  /// No description provided for @gradesAllWorks.
  ///
  /// In ru, this message translates to:
  /// **'Все работы'**
  String get gradesAllWorks;

  /// No description provided for @gradesNoSummative.
  ///
  /// In ru, this message translates to:
  /// **'СОР и СОЧ пока нет'**
  String get gradesNoSummative;

  /// No description provided for @gradesMark.
  ///
  /// In ru, this message translates to:
  /// **'Оценка'**
  String get gradesMark;

  /// No description provided for @gradesSor.
  ///
  /// In ru, this message translates to:
  /// **'СОР'**
  String get gradesSor;

  /// No description provided for @gradesSoch.
  ///
  /// In ru, this message translates to:
  /// **'СОЧ'**
  String get gradesSoch;

  /// No description provided for @gradesSorSoch.
  ///
  /// In ru, this message translates to:
  /// **'СОР/СОЧ'**
  String get gradesSorSoch;

  /// No description provided for @gradesWork.
  ///
  /// In ru, this message translates to:
  /// **'Работа'**
  String get gradesWork;

  /// No description provided for @gradesQuarter.
  ///
  /// In ru, this message translates to:
  /// **'{number} четверть'**
  String gradesQuarter(int number);

  /// No description provided for @gradesWeekEmpty.
  ///
  /// In ru, this message translates to:
  /// **'За неделю оценок пока нет'**
  String get gradesWeekEmpty;

  /// No description provided for @gradesWeekEmptyHint.
  ///
  /// In ru, this message translates to:
  /// **'Когда появятся новые оценки, я покажу их здесь.'**
  String get gradesWeekEmptyHint;

  /// No description provided for @gradesTotalsUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Итоговые данные пока недоступны'**
  String get gradesTotalsUnavailable;

  /// No description provided for @gradesYearAverage.
  ///
  /// In ru, this message translates to:
  /// **'Средний балл за год'**
  String get gradesYearAverage;

  /// No description provided for @gradesAverage.
  ///
  /// In ru, this message translates to:
  /// **'Средний балл'**
  String get gradesAverage;

  /// No description provided for @gradesForMonth.
  ///
  /// In ru, this message translates to:
  /// **'за {month}'**
  String gradesForMonth(String month);

  /// No description provided for @gradesKnowledgeQuality.
  ///
  /// In ru, this message translates to:
  /// **'Качество знаний'**
  String get gradesKnowledgeQuality;

  /// No description provided for @gradesForWeek.
  ///
  /// In ru, this message translates to:
  /// **'за неделю'**
  String get gradesForWeek;

  /// No description provided for @gradesDynamics.
  ///
  /// In ru, this message translates to:
  /// **'Динамика'**
  String get gradesDynamics;

  /// No description provided for @gradesSubject.
  ///
  /// In ru, this message translates to:
  /// **'Предмет'**
  String get gradesSubject;

  /// No description provided for @gradesExcellent.
  ///
  /// In ru, this message translates to:
  /// **'Отлично'**
  String get gradesExcellent;

  /// No description provided for @gradesGood.
  ///
  /// In ru, this message translates to:
  /// **'Хорошо'**
  String get gradesGood;

  /// No description provided for @gradesSatisfactoryShort.
  ///
  /// In ru, this message translates to:
  /// **'Удовл.'**
  String get gradesSatisfactoryShort;

  /// No description provided for @gradesAbsent.
  ///
  /// In ru, this message translates to:
  /// **'Не был'**
  String get gradesAbsent;

  /// No description provided for @gradesNoMark.
  ///
  /// In ru, this message translates to:
  /// **'Нет оценки'**
  String get gradesNoMark;

  /// No description provided for @gradesWeekSummary.
  ///
  /// In ru, this message translates to:
  /// **'Итоги недели'**
  String get gradesWeekSummary;

  /// No description provided for @gradesCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} оценка} few{{count} оценки} many{{count} оценок} other{{count} оценки}}'**
  String gradesCount(int count);

  /// No description provided for @gradesCountLabel.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{оценка} few{оценки} many{оценок} other{оценки}}'**
  String gradesCountLabel(int count);

  /// No description provided for @gradesAverageLower.
  ///
  /// In ru, this message translates to:
  /// **'средний балл'**
  String get gradesAverageLower;

  /// No description provided for @gradesAttendance.
  ///
  /// In ru, this message translates to:
  /// **'посещаемость'**
  String get gradesAttendance;

  /// No description provided for @gradesNeedImprove.
  ///
  /// In ru, this message translates to:
  /// **'Нужно подтянуть'**
  String get gradesNeedImprove;

  /// No description provided for @assistantTitle.
  ///
  /// In ru, this message translates to:
  /// **'Спросите Kundi'**
  String get assistantTitle;

  /// No description provided for @assistantSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Помощник по учёбе'**
  String get assistantSubtitle;

  /// No description provided for @assistantPastChats.
  ///
  /// In ru, this message translates to:
  /// **'Прошлые диалоги'**
  String get assistantPastChats;

  /// No description provided for @assistantNewChat.
  ///
  /// In ru, this message translates to:
  /// **'Новый диалог'**
  String get assistantNewChat;

  /// No description provided for @assistantDeleteChat.
  ///
  /// In ru, this message translates to:
  /// **'Удалить диалог'**
  String get assistantDeleteChat;

  /// No description provided for @assistantShowPrevious.
  ///
  /// In ru, this message translates to:
  /// **'Показать предыдущие сообщения'**
  String get assistantShowPrevious;

  /// No description provided for @assistantQuestionHint.
  ///
  /// In ru, this message translates to:
  /// **'Напишите вопрос…'**
  String get assistantQuestionHint;

  /// No description provided for @assistantGradeClass.
  ///
  /// In ru, this message translates to:
  /// **'{grade} класс'**
  String assistantGradeClass(int grade);

  /// No description provided for @assistantShowMore.
  ///
  /// In ru, this message translates to:
  /// **'Показать ещё'**
  String get assistantShowMore;

  /// No description provided for @assistantDeleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить диалог?'**
  String get assistantDeleteTitle;

  /// No description provided for @assistantDeleteBody.
  ///
  /// In ru, this message translates to:
  /// **'Историю этого диалога нельзя будет восстановить.'**
  String get assistantDeleteBody;

  /// No description provided for @assistantVoice.
  ///
  /// In ru, this message translates to:
  /// **'Голосом'**
  String get assistantVoice;

  /// No description provided for @assistantThinking.
  ///
  /// In ru, this message translates to:
  /// **'Kundi думает…'**
  String get assistantThinking;

  /// No description provided for @assistantEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Задайте вопрос — Kundi объяснит тему, даст подсказку или проверит ваш шаг.'**
  String get assistantEmpty;

  /// No description provided for @assistantLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить диалог.'**
  String get assistantLoadFailed;

  /// No description provided for @assistantHistoryRefreshFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обновить историю'**
  String get assistantHistoryRefreshFailed;

  /// No description provided for @assistantSuggestionExplain.
  ///
  /// In ru, this message translates to:
  /// **'Объясни тему'**
  String get assistantSuggestionExplain;

  /// No description provided for @assistantSuggestionFirstStep.
  ///
  /// In ru, this message translates to:
  /// **'Помоги сделать первый шаг'**
  String get assistantSuggestionFirstStep;

  /// No description provided for @assistantSuggestionCheck.
  ///
  /// In ru, this message translates to:
  /// **'Проверь мой ответ'**
  String get assistantSuggestionCheck;

  /// No description provided for @assistantRateLimited.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много запросов. Немного подождите и попробуйте снова.'**
  String get assistantRateLimited;

  /// No description provided for @assistantUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Kundi пока недоступна.'**
  String get assistantUnavailable;

  /// No description provided for @assistantTemporaryFailure.
  ///
  /// In ru, this message translates to:
  /// **'Kundi временно не смогла ответить. Попробуйте ещё раз.'**
  String get assistantTemporaryFailure;

  /// No description provided for @assistantSendFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отправить сообщение. Проверьте соединение.'**
  String get assistantSendFailed;

  /// No description provided for @voiceRecognizerUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Системное распознавание речи недоступно.'**
  String get voiceRecognizerUnavailable;

  /// No description provided for @voicePermissionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить микрофон?'**
  String get voicePermissionTitle;

  /// No description provided for @voicePermissionBody.
  ///
  /// In ru, this message translates to:
  /// **'Микрофон работает только во время удержания Kundi. Приложение не записывает и не хранит аудио. Системная служба устройства может обрабатывать речь локально или через своего поставщика. Распознанный текст сохраняется в истории диалога.'**
  String get voicePermissionBody;

  /// No description provided for @voiceNotNow.
  ///
  /// In ru, this message translates to:
  /// **'Не сейчас'**
  String get voiceNotNow;

  /// No description provided for @voiceHoldHint.
  ///
  /// In ru, this message translates to:
  /// **'Теперь удерживай Kundi и говори'**
  String get voiceHoldHint;

  /// No description provided for @voiceDisabledTitle.
  ///
  /// In ru, this message translates to:
  /// **'Микрофон выключен'**
  String get voiceDisabledTitle;

  /// No description provided for @voiceDisabledBody.
  ///
  /// In ru, this message translates to:
  /// **'Разрешение можно включить в настройках приложения. Текстовый помощник продолжает работать без микрофона.'**
  String get voiceDisabledBody;

  /// No description provided for @voiceOpenSettings.
  ///
  /// In ru, this message translates to:
  /// **'Открыть настройки'**
  String get voiceOpenSettings;

  /// No description provided for @voicePreparing.
  ///
  /// In ru, this message translates to:
  /// **'Подготавливаю Kundi…'**
  String get voicePreparing;

  /// No description provided for @voiceListening.
  ///
  /// In ru, this message translates to:
  /// **'Я слушаю… Говори, пока удерживаешь Kundi'**
  String get voiceListening;

  /// No description provided for @voiceProcessing.
  ///
  /// In ru, this message translates to:
  /// **'Обрабатываю речь…'**
  String get voiceProcessing;

  /// No description provided for @voiceThinking.
  ///
  /// In ru, this message translates to:
  /// **'Думаю…'**
  String get voiceThinking;

  /// No description provided for @voiceNoSpeech.
  ///
  /// In ru, this message translates to:
  /// **'Не расслышала. Попробуй ещё раз.'**
  String get voiceNoSpeech;

  /// No description provided for @voiceRecognitionFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось распознать речь.'**
  String get voiceRecognitionFailed;

  /// No description provided for @voicePlaybackFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось озвучить ответ.'**
  String get voicePlaybackFailed;

  /// No description provided for @voiceNoMatch.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось распознать речь на выбранном языке. Проверьте поддержку языка на устройстве и попробуйте ещё раз.'**
  String get voiceNoMatch;

  /// No description provided for @pullRefreshFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обновить данные. Старые данные сохранены.'**
  String get pullRefreshFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['kk', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'kk':
      return AppLocalizationsKk();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
