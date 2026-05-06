import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/theme/kundi_tokens.dart';
import '../../../shared/widgets/kundi_surface.dart';
import '../../profile/presentation/profile_page.dart';
import '../../summary/application/summary_controller.dart';
import '../../summary/domain/summary_entity.dart';
import '../application/lessons_controller.dart';
import '../domain/lessons_entity.dart';

class LessonsPage extends ConsumerWidget {
  const LessonsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonsState = ref.watch(lessonsControllerProvider);
    final summaryState = ref.watch(summaryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        leading: IconButton(
          icon: Icon(
            Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
          onPressed: () => ref.read(appThemeModeProvider.notifier).toggle(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
              );
            },
          ),
        ],
      ),
      body: KundiGradientBackground(
        child: SafeArea(
          child: lessonsState.when(
            data: (items) => ListView(
              padding: const EdgeInsets.fromLTRB(
                KundiSpace.sm,
                KundiSpace.sm,
                KundiSpace.sm,
                90,
              ),
              children: [
                _GreetingHero(summaryState: summaryState, lessons: items),
                const SizedBox(height: KundiSpace.sm),
                _TutorPlaceholderCard(
                  summaryState: summaryState,
                  lessons: items,
                ),
                const SizedBox(height: KundiSpace.sm),
                _UpcomingLessonsBlock(items: items),
              ],
            ),
            loading: () => const KundiStateBody.loading(),
            error: (error, _) => KundiStateBody.error(
              label: 'Не удалось загрузить главную',
              onRetry: () => ref
                  .read(lessonsControllerProvider.notifier)
                  .refreshFromCache(),
            ),
          ),
        ),
      ),
      bottomSheet: const _TutorChatSheetPlaceholder(),
    );
  }
}

class _GreetingHero extends StatelessWidget {
  const _GreetingHero({
    required this.summaryState,
    required this.lessons,
  });

  final AsyncValue<SummaryEntity> summaryState;
  final List<LessonsEntity> lessons;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = switch (now.hour) {
      <= 5 => 'Уже поздно, пора отдыхать',
      < 12 => 'Доброе утро',
      < 18 => 'Добрый день',
      _ => 'Добрый вечер',
    };

    return KundiSectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_weekdayLabel(now.weekday)}, ${now.day} ${_monthLabel(now.month)}',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.kundiTextSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            greeting,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: KundiSpace.sm),
          summaryState.when(
            loading: () => const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => const Text('Сводка временно недоступна'),
            data: (summary) {
              final stats = _HomeUiStats.from(
                summary: summary,
                lessons: lessons,
                now: now,
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  KundiCircularStat(
                    label: 'ДЗ сегодня',
                    value: stats.dayHomeworkMetric,
                    icon: Icons.task_alt_outlined,
                  ),
                  KundiCircularStat(
                    label: 'ДЗ неделя',
                    value: stats.weekHomeworkMetric,
                    icon: Icons.calendar_view_week_outlined,
                  ),
                  KundiCircularStat(
                    label: 'Посещ.',
                    value: stats.attendanceMetric,
                    icon: Icons.fact_check_outlined,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TutorPlaceholderCard extends StatelessWidget {
  const _TutorPlaceholderCard({
    required this.summaryState,
    required this.lessons,
  });

  final AsyncValue<SummaryEntity> summaryState;
  final List<LessonsEntity> lessons;

  @override
  Widget build(BuildContext context) {
    final hint = summaryState.when(
      data: (summary) {
        final stats = _HomeUiStats.from(
          summary: summary,
          lessons: lessons,
          now: DateTime.now(),
        );
        final lines = <String>[
          stats.todayLessons == 0
              ? 'Сегодня уроков нет'
              : 'Сегодня ${stats.todayLessons} уроков',
          'Невыполненных ДЗ: ${stats.openHomework}',
        ];
        if (stats.dangerHint != null) {
          lines.add('⚠️ ${stats.dangerHint}');
        }
        return lines.join('\n');
      },
      loading: () => 'Загружаем напоминания…',
      error: (_, __) => 'Напоминания временно недоступны',
    );

    return KundiSectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KundiSectionHeader(title: 'Центр дня'),
          const SizedBox(height: 6),
          Text(hint),
          const SizedBox(height: KundiSpace.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KundiSpace.sm),
            decoration: BoxDecoration(
              borderRadius: KundiRadius.md,
              border:
                  Border.all(color: Theme.of(context).colorScheme.kundiBorder),
              color: Theme.of(context)
                  .colorScheme
                  .kundiElevated
                  .withValues(alpha: 0.35),
            ),
            child: const Row(
              children: [
                Icon(Icons.smart_toy_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Место для Unity AI-репетитора (скоро)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingLessonsBlock extends StatelessWidget {
  const _UpcomingLessonsBlock({required this.items});

  final List<LessonsEntity> items;

  @override
  Widget build(BuildContext context) {
    return KundiSectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KundiSectionHeader(title: 'Ближайшие уроки'),
          const SizedBox(height: KundiSpace.xs),
          if (items.isEmpty)
            const KundiEmptyState(
              icon: Icons.school_outlined,
              label: 'Уроки пока не загружены',
            )
          else
            ...items.take(4).map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: KundiSpace.xs),
                    padding: const EdgeInsets.all(KundiSpace.sm),
                    decoration: BoxDecoration(
                      borderRadius: KundiRadius.md,
                      color: Theme.of(context)
                          .colorScheme
                          .kundiElevated
                          .withValues(alpha: 0.3),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.subjectName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.startTime.isEmpty ? '—' : item.startTime}-${item.endTime.isEmpty ? '—' : item.endTime} • ${item.date}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text('Урок ${item.lessonNumber}'),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _TutorChatSheetPlaceholder extends StatelessWidget {
  const _TutorChatSheetPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: KundiRadius.lg,
          color: Theme.of(context)
              .colorScheme
              .kundiSurface
              .withValues(alpha: 0.95),
          border: Border.all(color: Theme.of(context).colorScheme.kundiBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Спросите Kundi…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.kundiTextSecondary,
                    ),
              ),
            ),
            Icon(
              Icons.north,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeUiStats {
  const _HomeUiStats({
    required this.dayHomeworkMetric,
    required this.weekHomeworkMetric,
    required this.attendanceMetric,
    required this.todayLessons,
    required this.openHomework,
    required this.dangerHint,
  });

  final String dayHomeworkMetric;
  final String weekHomeworkMetric;
  final String attendanceMetric;
  final int todayLessons;
  final int openHomework;
  final String? dangerHint;

  static _HomeUiStats from({
    required SummaryEntity summary,
    required List<LessonsEntity> lessons,
    required DateTime now,
  }) {
    final todayKey = _isoDate(now);
    final weekStart =
        now.subtract(Duration(days: now.weekday - DateTime.monday));
    final weekEnd = weekStart.add(const Duration(days: 6));

    final todayLessons =
        lessons.where((l) => l.date == todayKey).toList(growable: false);
    final weekLessons = lessons.where((lesson) {
      final parsed = DateTime.tryParse(lesson.date);
      if (parsed == null) {
        return false;
      }
      final local = DateTime(parsed.year, parsed.month, parsed.day);
      return !local.isBefore(
              DateTime(weekStart.year, weekStart.month, weekStart.day)) &&
          !local.isAfter(DateTime(weekEnd.year, weekEnd.month, weekEnd.day));
    }).toList(growable: false);

    final todayHomeworkTotal =
        todayLessons.where((l) => l.homeworkText.trim().isNotEmpty).length;
    final weekHomeworkTotal =
        weekLessons.where((l) => l.homeworkText.trim().isNotEmpty).length;

    final attendanceRows = lessons
        .where((l) => l.attendanceCode.trim().isNotEmpty)
        .toList(growable: false);
    final presentCount = attendanceRows
        .where((l) => l.attendanceCode.trim().toLowerCase() == 'present')
        .length;

    final attendanceMetric = attendanceRows.isEmpty
        ? 'данных нет'
        : '${((presentCount * 100) / attendanceRows.length).round()}%';

    final openHomework = todayHomeworkTotal;

    String? dangerHint;
    final hasRisk = weekLessons.any((lesson) {
      final text = '${lesson.topic} ${lesson.homeworkText}'.toLowerCase();
      return text.contains('контрольн') ||
          text.contains('сор') ||
          text.contains('соч');
    });
    if (hasRisk) {
      dangerHint = 'В ближайших уроках есть контрольная/СОР/СОЧ';
    }

    String dayHomeworkMetric;
    if (todayLessons.isEmpty) {
      dayHomeworkMetric = 'нет уроков';
    } else if (todayHomeworkTotal == 0) {
      dayHomeworkMetric = '0/0';
    } else {
      dayHomeworkMetric = '0/$todayHomeworkTotal';
    }

    String weekHomeworkMetric;
    if (weekLessons.isEmpty) {
      weekHomeworkMetric = 'нет уроков';
    } else if (weekHomeworkTotal == 0) {
      weekHomeworkMetric = '0/0';
    } else {
      weekHomeworkMetric = '0/$weekHomeworkTotal';
    }

    return _HomeUiStats(
      dayHomeworkMetric: dayHomeworkMetric,
      weekHomeworkMetric: weekHomeworkMetric,
      attendanceMetric: attendanceMetric,
      todayLessons: todayLessons.length,
      openHomework: openHomework,
      dangerHint: dangerHint,
    );
  }
}

String _weekdayLabel(int weekday) {
  const names = <int, String>{
    1: 'Понедельник',
    2: 'Вторник',
    3: 'Среда',
    4: 'Четверг',
    5: 'Пятница',
    6: 'Суббота',
    7: 'Воскресенье',
  };
  return names[weekday] ?? '';
}

String _monthLabel(int month) {
  const names = <int, String>{
    1: 'января',
    2: 'февраля',
    3: 'марта',
    4: 'апреля',
    5: 'мая',
    6: 'июня',
    7: 'июля',
    8: 'августа',
    9: 'сентября',
    10: 'октября',
    11: 'ноября',
    12: 'декабря',
  };
  return names[month] ?? '';
}

String _isoDate(DateTime value) {
  final mm = value.month.toString().padLeft(2, '0');
  final dd = value.day.toString().padLeft(2, '0');
  return '${value.year}-$mm-$dd';
}
