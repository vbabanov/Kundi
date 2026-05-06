import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/homework/presentation/homework_page.dart';
import 'package:kundi_mobile/features/lessons/application/lessons_controller.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_entity.dart';

void main() {
  testWidgets(
    'homework shell supports mode toggle, day switch, danger highlight',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
          ],
          child: const MaterialApp(home: HomeworkPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('ДЗ'), findsWidgets);
      expect(find.text('Тема'), findsWidgets);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      expect(find.textContaining('Algebra'), findsOneWidget);
      expect(find.text('Контроль'), findsOneWidget);
      expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
      expect(find.textContaining('Solve #12'), findsOneWidget);

      await tester.tap(find.text('Тема').first);
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.textContaining('Quadratic review (СОР)'), findsOneWidget);
    },
  );
}

class _FakeLessonsController extends LessonsController {
  @override
  Future<List<LessonsEntity>> build() async => const <LessonsEntity>[
        LessonsEntity(
          id: 'lesson-1',
          date: '2026-04-10',
          lessonNumber: 2,
          startTime: '08:30',
          endTime: '09:15',
          lessonPlace: '312',
          subjectName: 'Algebra',
          topic: 'Quadratic review (СОР)',
          homeworkText: 'Solve #12',
          requiresPhoto: false,
          gradeValue: '',
          attendanceCode: '',
        ),
        LessonsEntity(
          id: 'lesson-2',
          date: '2026-04-10',
          lessonNumber: 3,
          startTime: '09:20',
          endTime: '10:05',
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
