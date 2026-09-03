import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/kundi_native_avatar/kundi_home_avatar_diagnostics.dart';

void main() {
  test('normal lifecycle emits semantic events once in exact order', () {
    final recorder = _TelemetryRecorder();
    final telemetry = KundiHomeAvatarLifecycleTelemetry(
      recordDiagnostic: recorder.record,
    )..beginGeneration(7);

    expect(
      telemetry.recordHandoffCompleted(
        generation: 7,
        textureId: 42,
        mode: 'fade',
        durationMs: 90,
      ),
      isTrue,
    );
    expect(
      telemetry.startGreeting(
        generation: 7,
        textureId: 42,
        identity: 'home:greeting:1',
        animationName: 'Talking2',
        durationMs: 2600,
      ),
      isTrue,
    );
    expect(
      telemetry.completeGreeting(
        generation: 7,
        textureId: 42,
        identity: 'home:greeting:1',
        reason: KundiGreetingCompletionReason.finished,
      ),
      isTrue,
    );

    expect(
      recorder.names,
      <String>[
        KundiHomeAvatarTraceName.handoffCompleted,
        KundiHomeAvatarTraceName.greetingStarted,
        KundiHomeAvatarTraceName.greetingCompleted,
      ],
    );
    expect(recorder.events[0].payload, <String, Object?>{
      'mode': 'fade',
      'durationMs': 90,
    });
    expect(recorder.events[2].payload, <String, Object?>{
      'animationName': 'Talking2',
      'durationMs': 2600,
      'completionReason': 'finished',
    });
  });

  test('duplicate and stale callbacks are suppressed for a renderer generation',
      () {
    final recorder = _TelemetryRecorder();
    final telemetry = KundiHomeAvatarLifecycleTelemetry(
      recordDiagnostic: recorder.record,
    )..beginGeneration(3);

    expect(
      telemetry.recordHandoffCompleted(
        generation: 3,
        textureId: 42,
        mode: 'fade',
        durationMs: 90,
      ),
      isTrue,
    );
    expect(
      telemetry.recordHandoffCompleted(
        generation: 3,
        textureId: 42,
        mode: 'fade',
        durationMs: 90,
      ),
      isFalse,
    );
    expect(
      telemetry.startGreeting(
        generation: 3,
        textureId: 42,
        identity: 'home:greeting:3',
        animationName: 'Talking1',
        durationMs: 2600,
      ),
      isTrue,
    );
    expect(
      telemetry.completeGreeting(
        generation: 2,
        textureId: 42,
        identity: 'home:greeting:3',
        reason: KundiGreetingCompletionReason.finished,
      ),
      isFalse,
    );
    expect(recorder.names, <String>[
      KundiHomeAvatarTraceName.handoffCompleted,
      KundiHomeAvatarTraceName.greetingStarted,
    ]);
  });

  test('fatal suppression prevents late handoff and greeting completion', () {
    final recorder = _TelemetryRecorder();
    final telemetry = KundiHomeAvatarLifecycleTelemetry(
      recordDiagnostic: recorder.record,
    )..beginGeneration(4);
    telemetry.startGreeting(
      generation: 4,
      textureId: 42,
      identity: 'home:greeting:4',
      animationName: 'Talking3',
      durationMs: 2600,
    );

    telemetry.suppressGeneration(4);

    expect(
      telemetry.completeGreeting(
        generation: 4,
        textureId: 42,
        identity: 'home:greeting:4',
        reason: KundiGreetingCompletionReason.finished,
      ),
      isFalse,
    );
    expect(
      telemetry.recordHandoffCompleted(
        generation: 4,
        textureId: 42,
        mode: 'fade',
        durationMs: 90,
      ),
      isFalse,
    );
    expect(
      recorder.names,
      <String>[KundiHomeAvatarTraceName.greetingStarted],
    );
  });

  test('retained Home return does not repeat semantic events', () {
    final recorder = _TelemetryRecorder();
    final telemetry = KundiHomeAvatarLifecycleTelemetry(
      recordDiagnostic: recorder.record,
    )..beginGeneration(5);
    telemetry.recordHandoffCompleted(
      generation: 5,
      textureId: 42,
      mode: 'fade',
      durationMs: 90,
    );
    telemetry.startGreeting(
      generation: 5,
      textureId: 42,
      identity: 'home:greeting:5',
      animationName: 'Talking1',
      durationMs: 2600,
    );

    expect(
      telemetry.completeGreeting(
        generation: 5,
        textureId: 42,
        identity: 'home:greeting:5',
        reason: KundiGreetingCompletionReason.cancelled,
      ),
      isTrue,
    );
    expect(
      telemetry.recordHandoffCompleted(
        generation: 5,
        textureId: 42,
        mode: 'fade',
        durationMs: 90,
      ),
      isFalse,
    );
    expect(
      telemetry.startGreeting(
        generation: 5,
        textureId: 42,
        identity: 'home:greeting:6',
        animationName: 'Talking2',
        durationMs: 2600,
      ),
      isFalse,
    );
    telemetry.beginGeneration(6);
    expect(
      telemetry.recordHandoffCompleted(
        generation: 6,
        textureId: 99,
        mode: 'instant',
        durationMs: 0,
      ),
      isTrue,
    );
    expect(recorder.events[2].payload['completionReason'], 'cancelled');
    expect(recorder.events.last.generation, 6);
  });
}

final class _TelemetryRecorder {
  final List<KundiHomeAvatarTraceEvent> events = <KundiHomeAvatarTraceEvent>[];

  List<String> get names => events.map((event) => event.name).toList();

  void record(
    String name, {
    required int generation,
    int? textureId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    events.add(
      KundiHomeAvatarTraceEvent(
        name: name,
        timestamp: DateTime.utc(2026),
        generation: generation,
        textureId: textureId,
        payload: payload,
      ),
    );
  }
}
