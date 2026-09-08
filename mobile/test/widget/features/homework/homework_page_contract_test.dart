import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/homework/presentation/homework_page.dart';
import 'package:kundi_mobile/features/lessons/application/lessons_controller.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_entity.dart';
import 'package:kundi_mobile/shared/theme/app_theme.dart';
import 'package:kundi_mobile/shared/widgets/student_pull_to_refresh.dart';

void main() {
  testWidgets('homework page renders header/selector/summary/mode/button',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
        ],
        child: const MaterialApp(home: HomeworkPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ДЗ'), findsWidgets);
    expect(find.byKey(const Key('homework-week-switcher')), findsNothing);
    expect(find.byKey(const Key('homework-week-day-selector')), findsOneWidget);
    expect(find.byKey(const Key('homework-summary-card')), findsOneWidget);
    expect(find.byKey(const Key('homework-mode-toggle')), findsOneWidget);
    expect(find.text('Тема урока'), findsOneWidget);
    expect(find.text('Отправить в WhatsApp за сегодня'), findsOneWidget);
    expect(find.text('Пн'), findsOneWidget);
    expect(find.text('Вт'), findsOneWidget);
    expect(find.text('Ср'), findsOneWidget);
    expect(find.text('Чт'), findsOneWidget);
    expect(find.text('Пт'), findsOneWidget);
    expect(find.text('Сб'), findsOneWidget);
    expect(find.text('Вс'), findsOneWidget);
  });

  testWidgets('homework mode shows homework text and time', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
        ],
        child: const MaterialApp(home: HomeworkPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Algebra'), findsOneWidget);
    expect(find.textContaining('Solve #12'), findsOneWidget);
    expect(find.text('08:30 — 09:15'), findsOneWidget);
  });

  testWidgets('topic mode shows topic text', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
        ],
        child: const MaterialApp(home: HomeworkPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Тема урока'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Quadratic review (СОР)'), findsOneWidget);
    expect(find.textContaining('Solve #12'), findsNothing);
  });

  testWidgets('empty state shows no lessons message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider
              .overrideWith(_FakeLessonsEmptyController.new),
        ],
        child: const MaterialApp(home: HomeworkPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('homework-empty-day-card')), findsOneWidget);
    expect(find.text('На этот день уроков нет'), findsOneWidget);
  });

  testWidgets('no mojibake patterns in homework page labels', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
        ],
        child: const MaterialApp(home: HomeworkPage()),
      ),
    );
    await tester.pumpAndSettle();

    final allTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .join(' ');
    for (final bad in ['Рђ', 'Рџ', 'вЂ', 'Ð', 'Ñ']) {
      expect(allTexts.contains(bad), isFalse);
    }
  });

  testWidgets('homework pull gesture uses shared refresh action',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider
              .overrideWith(_FakeLessonsEmptyController.new),
          studentRefreshActionProvider.overrideWithValue(() async {
            calls += 1;
          }),
        ],
        child: const MaterialApp(home: HomeworkPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('homework-pull-scroll')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('light theme keeps homework header controls readable',
      (tester) async {
    final theme = AppTheme.light;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
        ],
        child: MaterialApp(theme: theme, home: const HomeworkPage()),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester
        .widgetList<Text>(find.text('ДЗ'))
        .firstWhere((text) => text.style?.fontSize == 24);
    final menuIcon = tester.widget<Icon>(find.byIcon(Icons.menu_rounded));

    expect(title.style?.color, theme.colorScheme.onSurface);
    expect(menuIcon.color, theme.colorScheme.onSurface);
  });
}

class _FakeLessonsController extends LessonsController {
  @override
  Future<List<LessonsEntity>> build() async => const <LessonsEntity>[
        LessonsEntity(
          id: 'lesson-1',
          date: '2026-04-10',
          lessonNumber: 1,
          startTime: '08:30',
          endTime: '09:15',
          lessonPlace: '312',
          subjectName: 'Algebra',
          topic: 'Quadratic review (СОР)',
          homeworkText: 'Solve #12',
          requiresPhoto: false,
          gradeValue: '5',
          attendanceCode: '',
        ),
        LessonsEntity(
          id: 'lesson-2',
          date: '2026-04-10',
          lessonNumber: 2,
          startTime: '09:25',
          endTime: '10:10',
          lessonPlace: '207',
          subjectName: 'Biology',
          topic: 'Cells',
          homeworkText: 'Read p.45',
          requiresPhoto: false,
          gradeValue: '',
          attendanceCode: '',
        ),
      ];

  @override
  Future<void> refreshFromCache() async {
    state = await AsyncValue.guard(build);
  }
}

class _FakeLessonsEmptyController extends LessonsController {
  @override
  Future<List<LessonsEntity>> build() async => const <LessonsEntity>[];

  @override
  Future<void> refreshFromCache() async {
    state = await AsyncValue.guard(build);
  }
}
