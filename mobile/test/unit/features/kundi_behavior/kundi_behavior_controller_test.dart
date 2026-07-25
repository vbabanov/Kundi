import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/kundi_behavior/application/kundi_behavior_clock.dart';
import 'package:kundi_mobile/features/kundi_behavior/application/kundi_behavior_controller.dart';
import 'package:kundi_mobile/features/kundi_behavior/domain/kundi_behavior_event.dart';
import 'package:kundi_mobile/features/kundi_behavior/domain/kundi_behavior_state.dart';

void main() {
  late _FakeClock clock;
  late KundiBehaviorController controller;

  setUp(() {
    clock = _FakeClock(DateTime.utc(2026, 7, 25, 10));
    controller = KundiBehaviorController(clock: clock);
  });

  tearDown(() {
    controller.dispose();
  });

  test('timeout is deterministic and returns transient state to neutral', () {
    controller.dispatch(
      _event(
        clock,
        KundiBehaviorEventType.homeworkCompleted,
        'celebrate-1',
        duration: const Duration(seconds: 3),
      ),
    );

    expect(controller.state.kind, KundiBehaviorKind.celebrating);
    expect(clock.activeCount, 1);

    clock.advance(const Duration(seconds: 2));
    expect(controller.state.kind, KundiBehaviorKind.celebrating);

    clock.advance(const Duration(seconds: 1));
    expect(controller.state.kind, KundiBehaviorKind.neutral);
    expect(clock.activeCount, 0);
  });

  test('transition cancels the old timer and keeps only the new one', () {
    controller.dispatch(
      _event(
        clock,
        KundiBehaviorEventType.homeworkCompleted,
        'celebrate-1',
      ),
    );
    final oldHandle = clock.handles.single;

    controller.dispatch(
      _event(
        clock,
        KundiBehaviorEventType.absenceDetected,
        'warning-1',
      ),
    );

    expect(oldHandle.canceled, isTrue);
    expect(clock.activeCount, 1);
    expect(controller.state.kind, KundiBehaviorKind.warning);
  });

  test('dispose cancels timers and blocks later state emissions', () {
    var emissions = 0;
    controller.addListener((_) => emissions++, fireImmediately: false);
    controller.dispatch(
      _event(
        clock,
        KundiBehaviorEventType.homeworkCompleted,
        'celebrate-1',
      ),
    );
    expect(emissions, 1);

    controller.dispose();
    expect(clock.activeCount, 0);
    expect(
      controller.dispatch(
        _event(
          clock,
          KundiBehaviorEventType.assistantFailure,
          'error-after-dispose',
        ),
      ),
      isFalse,
    );
    clock.advance(const Duration(minutes: 1));
    expect(emissions, 1);

    controller = KundiBehaviorController(clock: clock);
  });

  test('same id and fingerprint is debounced', () {
    final first = _event(
      clock,
      KundiBehaviorEventType.homeworkCompleted,
      'event-1',
      fingerprint: 'opaque-homework',
    );

    expect(controller.dispatch(first), isTrue);
    expect(controller.dispatch(first), isFalse);
    expect(controller.state.sourceEventId, 'event-1');
  });

  test('different ids sharing a fingerprint are accepted', () {
    expect(
      controller.dispatch(
        _event(
          clock,
          KundiBehaviorEventType.homeworkCompleted,
          'event-1',
          fingerprint: 'opaque-result',
        ),
      ),
      isTrue,
    );
    expect(
      controller.dispatch(
        _event(
          clock,
          KundiBehaviorEventType.newGrade,
          'event-2',
          fingerprint: 'opaque-result',
        ),
      ),
      isTrue,
    );
    expect(controller.state.sourceEventId, 'event-2');
  });

  test('dedup storage uses deterministic bounded eviction', () {
    controller.dispose();
    controller = KundiBehaviorController(
      clock: clock,
      maxDedupEntries: 2,
      debounceWindow: const Duration(minutes: 1),
    );

    for (var i = 1; i <= 3; i++) {
      controller.dispatch(
        _event(
          clock,
          KundiBehaviorEventType.homeVisible,
          'event-$i',
          fingerprint: 'opaque-$i',
        ),
      );
    }

    expect(controller.dedupEntryCount, 2);
    expect(
      controller.dispatch(
        _event(
          clock,
          KundiBehaviorEventType.homeVisible,
          'event-1',
          fingerprint: 'opaque-1',
        ),
      ),
      isTrue,
    );
  });

  test('repeated homeVisible is debounced without rebuild-driven timers', () {
    expect(controller.homeVisible(), isTrue);
    expect(controller.homeVisible(), isFalse);
    expect(controller.hasActiveTimeout, isFalse);

    clock.advance(const Duration(seconds: 31));
    controller.appOpened();
    expect(controller.homeVisible(), isTrue);
  });

  test('appOpened is emitted only once during the controller lifetime', () {
    expect(controller.appOpened(), isTrue);

    controller.dispatch(
      _event(
        clock,
        KundiBehaviorEventType.assistantFailure,
        'error-after-open',
      ),
    );
    clock.advance(const Duration(seconds: 31));

    expect(controller.appOpened(), isFalse);
    expect(controller.state.kind, KundiBehaviorKind.neutral);
    expect(controller.state.sourceEventId, 'timeout:error-after-open');
  });
}

KundiBehaviorEvent _event(
  _FakeClock clock,
  KundiBehaviorEventType type,
  String id, {
  String? fingerprint,
  Duration? duration,
}) {
  return KundiBehaviorEvent(
    type: type,
    id: id,
    occurredAt: clock.now(),
    fingerprint: fingerprint,
    duration: duration,
  );
}

class _FakeClock implements KundiBehaviorClock {
  _FakeClock(this._now);

  DateTime _now;
  final List<_FakeHandle> handles = <_FakeHandle>[];

  int get activeCount =>
      handles.where((handle) => !handle.canceled && !handle.fired).length;

  @override
  DateTime now() => _now;

  @override
  KundiBehaviorTimerHandle schedule(
    DateTime deadline,
    void Function() callback,
  ) {
    final handle = _FakeHandle(deadline, callback);
    handles.add(handle);
    return handle;
  }

  @override
  void cancel(KundiBehaviorTimerHandle handle) {
    if (handle is _FakeHandle) {
      handle.canceled = true;
    }
  }

  void advance(Duration duration) {
    _now = _now.add(duration);
    while (true) {
      final due = handles
          .where(
            (handle) =>
                !handle.canceled &&
                !handle.fired &&
                !handle.deadline.isAfter(_now),
          )
          .toList(growable: false)
        ..sort((left, right) => left.deadline.compareTo(right.deadline));
      if (due.isEmpty) {
        return;
      }
      final handle = due.first;
      handle.fired = true;
      handle.callback();
    }
  }
}

class _FakeHandle implements KundiBehaviorTimerHandle {
  _FakeHandle(this.deadline, this.callback);

  final DateTime deadline;
  final void Function() callback;
  bool canceled = false;
  bool fired = false;
}
