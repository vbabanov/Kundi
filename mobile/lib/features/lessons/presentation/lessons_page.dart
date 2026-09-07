import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../runtimes/kundi_native_avatar/kundi_home_avatar_loading_frame.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../../kundi_behavior/application/kundi_behavior_controller.dart';
import '../../kundi_behavior/presentation/kundi_home_presentation_adapter.dart';
import '../../profile/domain/profile_entity.dart';
import '../../profile/application/profile_controller.dart';
import '../../profile/presentation/profile_page.dart';
import '../../summary/application/summary_controller.dart';
import '../../summary/domain/summary_entity.dart';
import '../application/lessons_controller.dart';
import '../application/home_gamification_provider.dart';
import '../domain/home_gamification_metrics.dart';
import '../domain/home_greeting.dart';
import '../domain/lessons_entity.dart';
import 'widgets/kundi_home_hero.dart';
import '../../assistant/application/kundi_tts_coordinator.dart';

class LessonsPage extends ConsumerWidget {
  const LessonsPage({
    super.key,
    this.onHomeworkTap,
    this.onGradesTap,
    this.onAssistantTap,
    this.onAssistantPointerDown,
    this.onAssistantPointerUp,
    this.onAssistantPointerCancel,
    this.onAssistantLongPressStart,
    this.onAssistantLongPressEnd,
    this.onAssistantLongPressCancel,
    this.assistantEnabled = false,
    this.voiceStatusText = '',
    this.voiceListening = false,
    this.now,
    this.realtimeAvatarEnabled = false,
    this.realtimeAvatarPreparing = false,
    this.realtimeAvatarLoadingFrame,
    this.isHomeVisible = true,
  });

  static const _heroAssetPath = 'assets/images/kundi/home/kundi_home.webp';

  final VoidCallback? onHomeworkTap;
  final VoidCallback? onGradesTap;
  final VoidCallback? onAssistantTap;
  final PointerDownEventListener? onAssistantPointerDown;
  final PointerUpEventListener? onAssistantPointerUp;
  final PointerCancelEventListener? onAssistantPointerCancel;
  final GestureLongPressStartCallback? onAssistantLongPressStart;
  final GestureLongPressEndCallback? onAssistantLongPressEnd;
  final VoidCallback? onAssistantLongPressCancel;
  final bool assistantEnabled;
  final String voiceStatusText;
  final bool voiceListening;
  final DateTime? now;
  final bool realtimeAvatarEnabled;
  final bool realtimeAvatarPreparing;
  final KundiHomeAvatarLoadingFrame? realtimeAvatarLoadingFrame;
  final bool isHomeVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTime = now ?? DateTime.now();
    final lessonsState = ref.watch(lessonsControllerProvider);
    final metricsState =
        ref.watch(homeGamificationMetricsProvider(currentTime));
    final summaryState = ref.watch(summaryControllerProvider);
    final profileState = ref.watch(profileControllerProvider);
    final behaviorCoreEnabled = ref.watch(kundiBehaviorCoreEnabledProvider);
    final behaviorState =
        behaviorCoreEnabled ? ref.watch(kundiBehaviorControllerProvider) : null;
    final lessons = lessonsState.valueOrNull ?? const <LessonsEntity>[];
    final summary = summaryState.valueOrNull;
    final today = _TodaySnapshot.from(
      lessons: lessons,
      summary: summary,
      now: currentTime,
    );
    final identity = profileState.valueOrNull?.providerIdentity;
    final studentName = resolveStudentFirstName(
      explicitFirstName: identity?.studentFirstName ?? '',
      fullName: identity?.studentFullName ?? '',
    );
    final greeting = homeGreetingFor(currentTime, studentName);
    final heroMessage = _heroMessage(
      lessonsState: lessonsState,
      snapshot: today,
    );
    final semanticState = today.hasData
        ? 'План на сегодня доступен'
        : 'План на сегодня пока пуст';
    KundiHomePresentation? behaviorPresentation;
    if (behaviorState != null) {
      try {
        behaviorPresentation = const KundiHomePresentationAdapter().adapt(
          state: behaviorState,
          neutralTitle: greeting,
          neutralMessage: heroMessage,
          neutralSemanticLabel: semanticState,
        );
      } catch (_) {
        behaviorPresentation = null;
      }
    }
    final animationCueName =
        behaviorPresentation?.animationCueName ?? 'neutral';
    final animationIdentity =
        animationCueName == 'neutral' || behaviorState == null
            ? 'home:standing:initial'
            : behaviorState.sourceEventId;

    return Scaffold(
      body: KundiGradientBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            key: const Key('home-main-scroll'),
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 76),
            children: [
              _HomeHeader(
                onProfileTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfilePage(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              RepaintBoundary(
                key: const Key('home-summary-panel'),
                child: KeyedSubtree(
                  key: const Key('home-today-cards'),
                  child: _DailySummaryPanel(
                    metricsState: metricsState,
                  ),
                ),
              ),
              if (lessonsState.hasError) ...[
                const SizedBox(height: 8),
                _InlineLoadError(
                  onRetry: () => ref
                      .read(lessonsControllerProvider.notifier)
                      .refreshFromCache(),
                ),
              ],
              const SizedBox(height: 14),
              _HeroActionStack(
                greeting: behaviorPresentation?.title ?? greeting,
                dateLabel: russianDateLabel(currentTime),
                heroMessage: behaviorPresentation?.message ?? heroMessage,
                semanticState:
                    behaviorPresentation?.semanticLabel ?? semanticState,
                heroAssetPath: behaviorPresentation?.assetPath ??
                    LessonsPage._heroAssetPath,
                realtimeAvatarEnabled: realtimeAvatarEnabled,
                realtimeAvatarPreparing: realtimeAvatarPreparing,
                realtimeAvatarLoadingFrame: realtimeAvatarLoadingFrame,
                isHomeVisible: isHomeVisible,
                animationCueName: animationCueName,
                animationIdentity: animationIdentity,
                homeworkText: _homeworkActionText(today.homeworkCount),
                gradesTitle: _recentResultsTitle(summary),
                gradesText: _latestGradesText(summary),
                onHomeworkTap: onHomeworkTap,
                onGradesTap: onGradesTap,
                onAssistantTap: onAssistantTap,
                onAssistantPointerDown: onAssistantPointerDown,
                onAssistantPointerUp: onAssistantPointerUp,
                onAssistantPointerCancel: onAssistantPointerCancel,
                onAssistantLongPressStart: onAssistantLongPressStart,
                onAssistantLongPressEnd: onAssistantLongPressEnd,
                onAssistantLongPressCancel: onAssistantLongPressCancel,
                assistantEnabled: assistantEnabled,
                voiceStatusText: voiceStatusText,
                voiceListening: voiceListening,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onProfileTap});

  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Главная',
            key: const Key('home-header-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          key: const Key('home-profile-action'),
          tooltip: 'Профиль',
          onPressed: onProfileTap,
          style: IconButton.styleFrom(
            fixedSize: const Size(46, 46),
            backgroundColor: const Color(0x661F174B),
            side: const BorderSide(color: Color(0x806D55D9)),
          ),
          icon: const Icon(Icons.person_outline_rounded, color: Colors.white),
        ),
      ],
    );
  }
}

class _DailySummaryPanel extends StatelessWidget {
  const _DailySummaryPanel({required this.metricsState});

  final AsyncValue<HomeGamificationMetrics> metricsState;

  @override
  Widget build(BuildContext context) {
    final metrics = metricsState.valueOrNull;
    final loading = metricsState.isLoading && metrics == null;
    final hasError = metricsState.hasError && metrics == null;
    return Container(
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0x8F14123C),
        border: Border.all(color: const Color(0x72584CA0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x242F25A0),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _GamificationMetric(
              icon: Icons.task_alt_rounded,
              label: 'ДЗ сегодня',
              accent: const Color(0xFF63D6A7),
              metric: metrics?.homeworkToday,
              loading: loading,
              hasError: hasError,
            ),
          ),
          const _SummarySeparator(),
          Expanded(
            child: _GamificationMetric(
              icon: Icons.calendar_view_week_rounded,
              label: 'ДЗ за неделю',
              accent: const Color(0xFFFFB84D),
              metric: metrics?.homeworkWeek,
              loading: loading,
              hasError: hasError,
            ),
          ),
          const _SummarySeparator(),
          Expanded(
            child: _GamificationMetric(
              icon: Icons.verified_user_outlined,
              label: 'Посещаемость',
              accent: const Color(0xFF5EA3FF),
              metric: metrics?.attendance,
              loading: loading,
              hasError: hasError,
            ),
          ),
        ],
      ),
    );
  }
}

class _GamificationMetric extends StatelessWidget {
  const _GamificationMetric({
    required this.icon,
    required this.label,
    required this.accent,
    required this.metric,
    required this.loading,
    required this.hasError,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final HomeProgressMetric? metric;
  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    value: metric?.percent == null ? 0 : metric!.percent! / 100,
                    strokeWidth: 3.5,
                    backgroundColor: accent.withValues(alpha: 0.28),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                Icon(icon, size: 18, color: accent),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _valueLabel(metric, loading: loading, hasError: hasError),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFC9C1E8),
                  fontSize: 11,
                  height: 1.15,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            _supportingLabel(metric, loading: loading, hasError: hasError),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF887EAA),
                  fontSize: 10,
                ),
          ),
        ],
      ),
    );
  }
}

String _valueLabel(
  HomeProgressMetric? metric, {
  required bool loading,
  required bool hasError,
}) {
  if (loading || hasError || metric?.percent == null) {
    return '—';
  }
  return '${metric!.percent}%';
}

String _supportingLabel(
  HomeProgressMetric? metric, {
  required bool loading,
  required bool hasError,
}) {
  if (loading) {
    return 'Загрузка';
  }
  if (hasError) {
    return 'Нет данных';
  }
  if (metric?.percent == null) {
    return metric?.emptyLabel ?? 'Нет данных';
  }
  return '${metric!.completed}/${metric.total}';
}

class _SummarySeparator extends StatelessWidget {
  const _SummarySeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 72,
      color: const Color(0x665A4E92),
    );
  }
}

class _InlineLoadError extends StatelessWidget {
  const _InlineLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 17, color: Color(0xFFC6BCE5)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Показываем доступные данные',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFC6BCE5),
                ),
          ),
        ),
        IconButton(
          tooltip: 'Обновить',
          visualDensity: VisualDensity.compact,
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
      ],
    );
  }
}

class _HeroActionStack extends ConsumerWidget {
  const _HeroActionStack({
    required this.greeting,
    required this.dateLabel,
    required this.heroMessage,
    required this.semanticState,
    required this.heroAssetPath,
    required this.realtimeAvatarEnabled,
    required this.realtimeAvatarPreparing,
    required this.realtimeAvatarLoadingFrame,
    required this.isHomeVisible,
    required this.animationCueName,
    required this.animationIdentity,
    required this.homeworkText,
    required this.gradesTitle,
    required this.gradesText,
    required this.onHomeworkTap,
    required this.onGradesTap,
    required this.onAssistantTap,
    required this.onAssistantPointerDown,
    required this.onAssistantPointerUp,
    required this.onAssistantPointerCancel,
    required this.onAssistantLongPressStart,
    required this.onAssistantLongPressEnd,
    required this.onAssistantLongPressCancel,
    required this.assistantEnabled,
    required this.voiceStatusText,
    required this.voiceListening,
  });

  final String greeting;
  final String dateLabel;
  final String heroMessage;
  final String semanticState;
  final String heroAssetPath;
  final bool realtimeAvatarEnabled;
  final bool realtimeAvatarPreparing;
  final KundiHomeAvatarLoadingFrame? realtimeAvatarLoadingFrame;
  final bool isHomeVisible;
  final String animationCueName;
  final String animationIdentity;
  final String homeworkText;
  final String gradesTitle;
  final String gradesText;
  final VoidCallback? onHomeworkTap;
  final VoidCallback? onGradesTap;
  final VoidCallback? onAssistantTap;
  final PointerDownEventListener? onAssistantPointerDown;
  final PointerUpEventListener? onAssistantPointerUp;
  final PointerCancelEventListener? onAssistantPointerCancel;
  final GestureLongPressStartCallback? onAssistantLongPressStart;
  final GestureLongPressEndCallback? onAssistantLongPressEnd;
  final VoidCallback? onAssistantLongPressCancel;
  final bool assistantEnabled;
  final String voiceStatusText;
  final bool voiceListening;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(kundiTtsEnabledProvider)
        ? ref.watch(kundiTtsCoordinatorProvider)
        : const KundiTtsState();
    return Stack(
      key: const Key('home-hero-action-stack'),
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 292),
          child: RepaintBoundary(
            key: const Key('home-action-rows'),
            child: KeyedSubtree(
              key: const Key('home-quick-actions'),
              child: Column(
                children: [
                  _InformationActionRow(
                    key: const Key('home-action-homework'),
                    legacyKey: const Key('home-quick-action-homework'),
                    icon: Icons.menu_book_rounded,
                    title: 'ДЗ сегодня',
                    secondary: homeworkText,
                    accent: const Color(0xFFB05CFF),
                    overlapInset: 96,
                    onTap: onHomeworkTap,
                  ),
                  const SizedBox(height: 10),
                  _InformationActionRow(
                    key: const Key('home-action-grades'),
                    legacyKey: const Key('home-quick-action-grades'),
                    icon: Icons.bar_chart_rounded,
                    title: gradesTitle,
                    secondary: gradesText,
                    accent: const Color(0xFF4A8CFF),
                    onTap: onGradesTap,
                  ),
                  const SizedBox(height: 10),
                  _InformationActionRow(
                    key: const Key('home-action-kundi'),
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Спросите Kundi...',
                    secondary: assistantEnabled
                        ? 'Объяснит тему и поможет сделать первый шаг'
                        : 'Персональный помощник появится позже',
                    accent: const Color(0xFF9E7BFF),
                    trailingLabel: assistantEnabled ? '' : 'Скоро',
                    onTap: assistantEnabled ? onAssistantTap : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        KundiHomeHero(
          ttsState: ttsState,
          title: greeting,
          dateLabel: dateLabel,
          message: heroMessage,
          assetPath: heroAssetPath,
          semanticState: semanticState,
          realtimeAvatarEnabled: realtimeAvatarEnabled,
          realtimeAvatarPreparing: realtimeAvatarPreparing,
          preparedLoadingFrame: realtimeAvatarLoadingFrame,
          isVisible: isHomeVisible,
          animationCueName: animationCueName,
          animationIdentity: animationIdentity,
          onAvatarTap: onAssistantTap,
          onAvatarPointerDown: onAssistantPointerDown,
          onAvatarPointerUp: onAssistantPointerUp,
          onAvatarPointerCancel: onAssistantPointerCancel,
          onAvatarLongPressStart: onAssistantLongPressStart,
          onAvatarLongPressEnd: onAssistantLongPressEnd,
          onAvatarLongPressCancel: onAssistantLongPressCancel,
          voiceStatusText: ttsState.errorMessage.isNotEmpty
              ? ttsState.errorMessage
              : voiceStatusText,
          voiceListening: voiceListening,
        ),
      ],
    );
  }
}

class _InformationActionRow extends StatelessWidget {
  const _InformationActionRow({
    super.key,
    this.legacyKey,
    required this.icon,
    required this.title,
    required this.secondary,
    required this.accent,
    this.onTap,
    this.trailingLabel,
    this.overlapInset = 0,
  });

  final Key? legacyKey;
  final IconData icon;
  final String title;
  final String secondary;
  final Color accent;
  final VoidCallback? onTap;
  final String? trailingLabel;
  final double overlapInset;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      child: Material(
        color: const Color(0xA314123C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x66534A91)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: legacyKey,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 11, 14 + overlapInset, 11),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.12),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.68),
                      ),
                    ),
                    child: Icon(icon, size: 22, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          secondary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFFACA1D2),
                                    fontSize: 13,
                                    height: 1.2,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (trailingLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: const Color(0x332F285C),
                      ),
                      child: Text(
                        trailingLabel!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF998EBC),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ] else if (onTap != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9488BE),
                      size: 22,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodaySnapshot {
  const _TodaySnapshot({
    required this.lessonCount,
    required this.homeworkCount,
    required this.nextLessonTime,
    required this.nextLessonSubject,
  });

  final int lessonCount;
  final int homeworkCount;
  final String nextLessonTime;
  final String nextLessonSubject;

  bool get hasData => lessonCount > 0;

  static _TodaySnapshot from({
    required List<LessonsEntity> lessons,
    required SummaryEntity? summary,
    required DateTime now,
  }) {
    final dateKey = _isoDate(now);
    final todayLessons = lessons
        .where((lesson) => lesson.date == dateKey)
        .toList(growable: false)
      ..sort((a, b) {
        final timeComparison = a.startTime.compareTo(b.startTime);
        return timeComparison != 0
            ? timeComparison
            : a.lessonNumber.compareTo(b.lessonNumber);
      });
    final homeworkCount = todayLessons
        .where((lesson) => lesson.homeworkText.trim().isNotEmpty)
        .length;

    if (todayLessons.isNotEmpty) {
      final nextLesson = todayLessons.firstWhere(
        (lesson) => !_lessonHasFinished(lesson, now),
        orElse: () => todayLessons.first,
      );
      return _TodaySnapshot(
        lessonCount: todayLessons.length,
        homeworkCount: homeworkCount,
        nextLessonTime:
            nextLesson.startTime.trim().isEmpty ? '—' : nextLesson.startTime,
        nextLessonSubject: nextLesson.subjectName.trim().isEmpty
            ? 'Ближайший урок'
            : nextLesson.subjectName,
      );
    }

    SummaryLessonHighlightEntity? upcoming;
    for (final lesson
        in summary?.upcomingLessons ?? const <SummaryLessonHighlightEntity>[]) {
      if (lesson.lessonDate == dateKey) {
        upcoming = lesson;
        break;
      }
    }
    return _TodaySnapshot(
      lessonCount: 0,
      homeworkCount: 0,
      nextLessonTime: upcoming == null ? '—' : '№${upcoming.lessonNumber}',
      nextLessonSubject: upcoming?.subjectName.trim().isNotEmpty == true
          ? upcoming!.subjectName
          : 'Нет уроков',
    );
  }
}

String _heroMessage({
  required AsyncValue<List<LessonsEntity>> lessonsState,
  required _TodaySnapshot snapshot,
}) {
  if (lessonsState.isLoading && !snapshot.hasData) {
    return 'Собираю твой план на сегодня.';
  }
  if (lessonsState.hasError && !snapshot.hasData) {
    return 'Расписание временно недоступно. Попробуем обновить ещё раз.';
  }
  if (!snapshot.hasData) {
    return 'Давай посмотрим, что запланировано на сегодня.';
  }

  final lessonWord = _pluralize(
    snapshot.lessonCount,
    'урок',
    'урока',
    'уроков',
  );
  if (snapshot.homeworkCount == 0) {
    return 'Сегодня у тебя ${snapshot.lessonCount} $lessonWord. '
        'Ближайший — ${snapshot.nextLessonSubject}.';
  }
  return 'Сегодня у тебя ${snapshot.lessonCount} $lessonWord. '
      'На сегодня ${snapshot.homeworkCount} '
      '${_pluralize(snapshot.homeworkCount, 'задание', 'задания', 'заданий')}.';
}

String _homeworkActionText(int homeworkCount) {
  if (homeworkCount == 0) {
    return 'Заданий на сегодня нет';
  }
  return '$homeworkCount '
      '${_pluralize(homeworkCount, 'задание', 'задания', 'заданий')} на сегодня';
}

String _latestGradesText(SummaryEntity? summary) {
  final values =
      (summary?.recentResults ?? const <SummaryResultHighlightEntity>[])
          .map((result) => result.valueText.trim())
          .where((value) => value.isNotEmpty)
          .take(3)
          .toList(growable: false);
  return values.isEmpty ? 'Новых оценок нет' : values.join(' • ');
}

String _recentResultsTitle(SummaryEntity? summary) {
  final kinds =
      (summary?.recentResults ?? const <SummaryResultHighlightEntity>[])
          .map((result) => result.resultKind.trim().toLowerCase())
          .where((kind) => kind.isNotEmpty)
          .toSet();
  const nonRegularKinds = <String>{'sor', 'soch', 'term', 'year', 'aggregate'};
  return kinds.any(nonRegularKinds.contains)
      ? 'Последние результаты'
      : 'Последние оценки';
}

String _pluralize(int value, String one, String few, String many) {
  final mod10 = value % 10;
  final mod100 = value % 100;
  if (mod10 == 1 && mod100 != 11) {
    return one;
  }
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return few;
  }
  return many;
}

bool _lessonHasFinished(LessonsEntity lesson, DateTime now) {
  final parts = lesson.endTime.split(':');
  if (parts.length != 2) {
    return false;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return false;
  }
  return now.isAfter(DateTime(now.year, now.month, now.day, hour, minute));
}

String _isoDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
