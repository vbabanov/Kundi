import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/assistant/application/assistant_controller.dart';
import 'package:kundi_mobile/features/assistant/application/kundi_voice_assistant_coordinator.dart';
import 'package:kundi_mobile/features/assistant/assistant_feature.dart';
import 'package:kundi_mobile/features/auth/presentation/main_shell_page.dart';
import 'package:kundi_mobile/features/grades/application/grades_controller.dart';
import 'package:kundi_mobile/features/grades/domain/grades_entity.dart';
import 'package:kundi_mobile/features/homework/application/homework_controller.dart';
import 'package:kundi_mobile/features/homework/domain/homework_entity.dart';
import 'package:kundi_mobile/features/lessons/application/lessons_controller.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_entity.dart';
import 'package:kundi_mobile/features/profile/application/profile_controller.dart';
import 'package:kundi_mobile/features/profile/domain/profile_entity.dart';
import 'package:kundi_mobile/features/summary/application/summary_controller.dart';
import 'package:kundi_mobile/features/summary/domain/summary_entity.dart';
import 'package:kundi_mobile/runtimes/kundi_system_speech/kundi_system_speech_transport.dart';

void main() {
  testWidgets('root shell uses swipe-first 3-page contract', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
          homeworkControllerProvider.overrideWith(_FakeHomeworkController.new),
          gradesControllerProvider.overrideWith(_FakeGradesController.new),
          profileControllerProvider.overrideWith(_FakeProfileController.new),
          summaryControllerProvider.overrideWith(_FakeSummaryController.new),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Главная'), findsWidgets);

    await tester.drag(find.byType(PageView), const Offset(-450, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grades-tab-main')), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('homework-week-day-selector')), findsOneWidget);
  });

  testWidgets('homework mode/day state survives root swipe transitions',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
          homeworkControllerProvider.overrideWith(_FakeHomeworkController.new),
          gradesControllerProvider.overrideWith(_FakeGradesController.new),
          profileControllerProvider.overrideWith(_FakeProfileController.new),
          summaryControllerProvider.overrideWith(_FakeSummaryController.new),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('Solve #12'), findsOneWidget);
    await tester.tap(find.text('Тема урока'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Квадратичные уравнения'), findsOneWidget);

    await tester.tap(find.byKey(const Key('homework-weekday-chip-6-off')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Электролиты и растворы'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-450, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-450, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('Электролиты и растворы'), findsOneWidget);
    expect(find.textContaining('Solve #12'), findsNothing);
  });

  testWidgets('denied permission leaves the next independent tap available',
      (tester) async {
    final speech = _WidgetFakeSpeechTransport(
      permission: KundiSpeechPermission.required,
      requestedPermission: KundiSpeechPermission.denied,
    );
    await _pumpVoiceShell(tester, speech);

    await _startLongPress(tester);
    expect(find.text('Разрешить микрофон?'), findsOneWidget);
    await tester.tap(find.text('Не сейчас'));
    await tester.pumpAndSettle();

    expect(speech.startCalls, 0);
    await tester.tap(find.byKey(const Key('kundi-home-avatar-gesture')));
    await tester.pumpAndSettle();
    expect(find.text('Спросите Kundi'), findsOneWidget);
  });

  testWidgets('permanently denied dialog leaves the next tap available',
      (tester) async {
    final speech = _WidgetFakeSpeechTransport(
      permission: KundiSpeechPermission.permanentlyDenied,
    );
    await _pumpVoiceShell(tester, speech);

    await _startLongPress(tester);
    expect(find.text('Микрофон выключен'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();

    expect(speech.startCalls, 0);
    await tester.tap(find.byKey(const Key('kundi-home-avatar-gesture')));
    await tester.pumpAndSettle();
    expect(find.text('Спросите Kundi'), findsOneWidget);
  });

  testWidgets('successful long press does not navigate, next tap does',
      (tester) async {
    final speech = _WidgetFakeSpeechTransport(
      permission: KundiSpeechPermission.granted,
    );
    await _pumpVoiceShell(tester, speech);

    await tester.longPress(find.byKey(const Key('kundi-home-avatar-gesture')));
    await tester.pumpAndSettle();

    expect(speech.startCalls, 1);
    expect(find.text('Спросите Kundi'), findsNothing);
    await tester.tap(find.byKey(const Key('kundi-home-avatar-gesture')));
    await tester.pumpAndSettle();
    expect(find.text('Спросите Kundi'), findsOneWidget);
  });

  testWidgets('cancelled long press leaves the next tap available',
      (tester) async {
    final speech = _WidgetFakeSpeechTransport(
      permission: KundiSpeechPermission.required,
    );
    final availability = Completer<bool>();
    speech.availabilityResult = availability.future;
    await _pumpVoiceShell(tester, speech);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('kundi-home-avatar-gesture'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    await gesture.cancel();
    availability.complete(true);
    await tester.pumpAndSettle();

    expect(speech.startCalls, 0);
    await tester.tap(find.byKey(const Key('kundi-home-avatar-gesture')));
    await tester.pumpAndSettle();
    expect(find.text('Спросите Kundi'), findsOneWidget);
  });

  testWidgets('voice flag false keeps tap available without speech API use',
      (tester) async {
    final speech = _WidgetFakeSpeechTransport(
      permission: KundiSpeechPermission.granted,
    );
    await _pumpVoiceShell(tester, speech, voiceEnabled: false);

    await tester.tap(find.byKey(const Key('kundi-home-avatar-gesture')));
    await tester.pumpAndSettle();

    expect(speech.permissionStatusCalls, 0);
    expect(speech.startCalls, 0);
    expect(find.text('Спросите Kundi'), findsOneWidget);
  });
}

Future<void> _pumpVoiceShell(
  WidgetTester tester,
  _WidgetFakeSpeechTransport speech, {
  bool voiceEnabled = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        kundiAssistantEnabledProvider.overrideWithValue(true),
        kundiVoiceInputEnabledProvider.overrideWithValue(voiceEnabled),
        assistantControllerProvider.overrideWith(_FakeAssistantController.new),
        kundiSystemSpeechTransportProvider.overrideWithValue(speech),
        lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
        homeworkControllerProvider.overrideWith(_FakeHomeworkController.new),
        gradesControllerProvider.overrideWith(_FakeGradesController.new),
        profileControllerProvider.overrideWith(_FakeProfileController.new),
        summaryControllerProvider.overrideWith(_FakeSummaryController.new),
      ],
      child: const MaterialApp(home: MainShellPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _startLongPress(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('kundi-home-avatar-gesture'))),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

class _FakeAssistantController extends AssistantController {
  @override
  Future<AssistantViewState> build() async => const AssistantViewState();
}

class _WidgetFakeSpeechTransport implements KundiSystemSpeechTransport {
  _WidgetFakeSpeechTransport({
    required this.permission,
    this.requestedPermission = KundiSpeechPermission.granted,
  });

  final StreamController<KundiSystemSpeechEvent> _events =
      StreamController<KundiSystemSpeechEvent>.broadcast(sync: true);
  KundiSpeechPermission permission;
  KundiSpeechPermission requestedPermission;
  Future<bool>? availabilityResult;
  int permissionStatusCalls = 0;
  int startCalls = 0;

  @override
  Stream<KundiSystemSpeechEvent> get events => _events.stream;

  @override
  Future<bool> availability() async =>
      availabilityResult == null ? true : await availabilityResult!;

  @override
  Future<KundiSpeechPermission> permissionStatus() async {
    permissionStatusCalls++;
    return permission;
  }

  @override
  Future<KundiSpeechPermission> requestPermission() async =>
      requestedPermission;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<bool> startListening({
    required String requestId,
    required String locale,
    bool partialResults = true,
    int maxResults = 3,
    bool qaTelemetryEnabled = false,
  }) async {
    startCalls++;
    _events.add(KundiSystemSpeechEvent('listeningStarted', <String, dynamic>{
      'requestId': requestId,
    }));
    return true;
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancelListening() async {}

  @override
  Future<void> dispose() => _events.close();
}

class _FakeLessonsController extends LessonsController {
  @override
  Future<List<LessonsEntity>> build() async => _fakeLessons;

  @override
  Future<void> refreshFromCache() async {
    state = const AsyncData<List<LessonsEntity>>(_fakeLessons);
  }
}

class _FakeHomeworkController extends HomeworkController {
  @override
  Future<List<HomeworkEntity>> build() async => const <HomeworkEntity>[
        HomeworkEntity(
          id: 'hw-1',
          description: 'Read chapter',
          requiresPhoto: false,
          lessonDate: '2026-04-10',
          subjectName: 'Biology',
        ),
      ];

  @override
  Future<void> refreshFromCache() async {
    state = const AsyncData<List<HomeworkEntity>>(<HomeworkEntity>[
      HomeworkEntity(
        id: 'hw-1',
        description: 'Read chapter',
        requiresPhoto: false,
        lessonDate: '2026-04-10',
        subjectName: 'Biology',
      ),
    ]);
  }
}

class _FakeGradesController extends GradesController {
  @override
  Future<GradesScreenData> build() async => _fakeGradesData;

  @override
  Future<void> refreshFromCache() async {
    state = const AsyncData<GradesScreenData>(_fakeGradesData);
  }
}

class _FakeProfileController extends ProfileController {
  @override
  Future<ProfileEntity?> build() async => const ProfileEntity(
        readMode: 'v2',
        providerIdentity: ProviderIdentityProfileSection(
          studentId: 'student-1',
          provider: 'kundelik',
          providerAccountRef: 'acc-1',
          providerPersonId: 'person-1',
          providerSchoolId: 'school-1',
          providerGroupId: 'group-1',
          studentFullName: 'Artem Babanov',
          schoolName: 'Kundi School',
          classLabel: '7A',
          classTeacherFullName: 'Teacher',
          gradeLevel: 7,
        ),
        localAppProfile: null,
      );

  @override
  Future<void> refreshFromCache() async {
    state = await AsyncValue.guard(build);
  }
}

class _FakeSummaryController extends SummaryController {
  @override
  Future<SummaryEntity> build() async => SummaryEntity.empty;

  @override
  Future<void> refreshFromCache() async {
    state = const AsyncData<SummaryEntity>(SummaryEntity.empty);
  }
}

const _fakeLessons = <LessonsEntity>[
  LessonsEntity(
    id: 'lesson-1',
    date: '2026-04-10',
    lessonNumber: 1,
    startTime: '08:30',
    endTime: '09:15',
    subjectName: 'Algebra',
    topic: 'Квадратичные уравнения',
    homeworkText: 'Solve #12',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
  LessonsEntity(
    id: 'lesson-2',
    date: '2026-04-11',
    lessonNumber: 2,
    startTime: '09:20',
    endTime: '10:05',
    subjectName: 'Chemistry',
    topic: 'Электролиты и растворы',
    homeworkText: 'Параграф 18',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
];

const _fakeGradesData = GradesScreenData(
  readMode: 'v2',
  provider: 'kundelik',
  windowKey: 'wk',
  snapshotAt: '2026-04-10T00:00:00Z',
  availableWeeks: <GradesWeekOption>[],
  weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{},
  latestRegularResults: <LatestRegularResultItem>[
    LatestRegularResultItem(
      subjectKey: 'sub-1',
      subjectName: 'Algebra',
      value: '8',
      recordedOn: '2026-04-10',
      mood: 'good',
    ),
  ],
  summativeBySubject: <SubjectSummativeSection>[],
  aggregatesBySubject: <SubjectAggregateSection>[],
);
