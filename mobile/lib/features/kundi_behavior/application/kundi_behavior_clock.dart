import 'dart:async';

abstract interface class KundiBehaviorTimerHandle {}

abstract interface class KundiBehaviorClock {
  DateTime now();

  KundiBehaviorTimerHandle schedule(
    DateTime deadline,
    void Function() callback,
  );

  void cancel(KundiBehaviorTimerHandle handle);
}

class SystemKundiBehaviorClock implements KundiBehaviorClock {
  const SystemKundiBehaviorClock();

  @override
  DateTime now() => DateTime.now();

  @override
  KundiBehaviorTimerHandle schedule(
    DateTime deadline,
    void Function() callback,
  ) {
    final delay = deadline.difference(now());
    return _SystemTimerHandle(
      Timer(delay.isNegative ? Duration.zero : delay, callback),
    );
  }

  @override
  void cancel(KundiBehaviorTimerHandle handle) {
    if (handle is _SystemTimerHandle) {
      handle.timer.cancel();
    }
  }
}

class _SystemTimerHandle implements KundiBehaviorTimerHandle {
  const _SystemTimerHandle(this.timer);

  final Timer timer;
}
