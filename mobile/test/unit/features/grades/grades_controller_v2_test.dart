import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/grades/application/grades_controller.dart';
import 'package:kundi_mobile/features/grades/domain/grades_entity.dart';
import 'package:kundi_mobile/features/grades/domain/grades_repository.dart';

void main() {
  test('controller exposes v2 grades data from repository', () async {
    final repo = _FakeGradesRepository([
      _data('2026-04-05T12:00:00Z'),
    ]);
    final container = ProviderContainer(
      overrides: [
        gradesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    final data = await container.read(gradesControllerProvider.future);

    expect(data.readMode, 'v2');
    expect(data.availableWeeks, hasLength(1));
    expect(repo.calls, 1);
  });

  test('refreshFromCache updates state', () async {
    final repo = _FakeGradesRepository([
      _data('2026-04-05T12:00:00Z'),
      _data('2026-04-05T12:05:00Z'),
    ]);
    final container = ProviderContainer(
      overrides: [
        gradesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await container.read(gradesControllerProvider.future);
    await container.read(gradesControllerProvider.notifier).refreshFromCache();
    final state = container.read(gradesControllerProvider);

    expect(state.hasValue, isTrue);
    expect(state.value!.snapshotAt, '2026-04-05T12:05:00Z');
    expect(repo.calls, 2);
  });
}

class _FakeGradesRepository implements GradesRepository {
  _FakeGradesRepository(this._responses);

  final List<GradesScreenData> _responses;
  int calls = 0;

  @override
  Future<GradesScreenData> get() async {
    final index = calls < _responses.length ? calls : _responses.length - 1;
    calls += 1;
    return _responses[index];
  }
}

GradesScreenData _data(String snapshotAt) {
  return GradesScreenData(
    readMode: 'v2',
    provider: 'kundelik',
    windowKey: 'wk',
    snapshotAt: snapshotAt,
    availableWeeks: const [
      GradesWeekOption(
        weekKey: '2026-04-06',
        weekStartDate: '2026-04-06',
        weekEndDate: '2026-04-12',
        label: '06.04 - 12.04',
      ),
    ],
    weeklyRowsByWeek: const {
      '2026-04-06': [
        WeeklySubjectGradesRow(
          subjectKey: 'math',
          subjectName: 'Algebra',
          cellsByWeekday: {
            1: WeeklyGradeCell(
              date: '2026-04-06',
              hasLesson: true,
              regularMarks: ['9'],
              attendanceCodes: [],
            ),
          },
        ),
      ],
    },
    latestRegularResults: const [
      LatestRegularResultItem(
        subjectKey: 'math',
        subjectName: 'Algebra',
        value: '9',
        recordedOn: '2026-04-06',
        mood: 'good',
      ),
    ],
    summativeBySubject: const [],
    aggregatesBySubject: const [],
  );
}
