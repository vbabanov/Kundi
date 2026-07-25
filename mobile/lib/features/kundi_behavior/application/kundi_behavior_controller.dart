import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/kundi_behavior_event.dart';
import '../domain/kundi_behavior_reducer.dart';
import '../domain/kundi_behavior_state.dart';
import 'kundi_behavior_clock.dart';

const bool kundiBehaviorCoreEnabledByDefault = bool.fromEnvironment(
  'ENABLE_KUNDI_BEHAVIOR_CORE',
  defaultValue: false,
);

final kundiBehaviorCoreEnabledProvider = Provider<bool>(
  (ref) => kundiBehaviorCoreEnabledByDefault,
);

final kundiBehaviorControllerProvider =
    StateNotifierProvider.autoDispose<
      KundiBehaviorController,
      KundiBehaviorState
    >((ref) {
      return KundiBehaviorController(clock: const SystemKundiBehaviorClock());
    });

class KundiBehaviorController extends StateNotifier<KundiBehaviorState> {
  KundiBehaviorController({
    required KundiBehaviorClock clock,
    KundiBehaviorReducer reducer = const KundiBehaviorReducer(),
    Duration debounceWindow = const Duration(seconds: 30),
    int maxDedupEntries = 128,
  }) : _clock = clock,
       _reducer = reducer,
       _debounceWindow = debounceWindow,
       _maxDedupEntries = maxDedupEntries < 1 ? 1 : maxDedupEntries,
       super(
         KundiBehaviorState.neutral(
           enteredAt: clock.now(),
           sourceEventId: 'controller:initial',
         ),
       );

  final KundiBehaviorClock _clock;
  final KundiBehaviorReducer _reducer;
  final Duration _debounceWindow;
  final int _maxDedupEntries;
  final LinkedHashMap<String, DateTime> _dedup = LinkedHashMap();

  KundiBehaviorTimerHandle? _timeoutHandle;
  bool _appOpenedEmitted = false;
  bool _disposed = false;

  int get dedupEntryCount => _dedup.length;
  bool get hasActiveTimeout => _timeoutHandle != null;

  bool appOpened() {
    if (_disposed || _appOpenedEmitted) {
      return false;
    }
    _appOpenedEmitted = true;
    return dispatch(
      KundiBehaviorEvent(
        type: KundiBehaviorEventType.appOpened,
        id: 'lifecycle:app-opened',
        occurredAt: _clock.now(),
        fingerprint: 'lifecycle:app-opened',
      ),
    );
  }

  bool homeVisible() {
    return dispatch(
      KundiBehaviorEvent(
        type: KundiBehaviorEventType.homeVisible,
        id: 'lifecycle:home-visible',
        occurredAt: _clock.now(),
        fingerprint: 'lifecycle:home-visible',
      ),
    );
  }

  bool interrupt() {
    return dispatch(
      KundiBehaviorEvent(
        type: KundiBehaviorEventType.userInterrupted,
        id: 'command:interrupt:${_clock.now().microsecondsSinceEpoch}',
        occurredAt: _clock.now(),
      ),
    );
  }

  bool dismiss() {
    return dispatch(
      KundiBehaviorEvent(
        type: KundiBehaviorEventType.dismissed,
        id: 'command:dismiss:${_clock.now().microsecondsSinceEpoch}',
        occurredAt: _clock.now(),
      ),
    );
  }

  bool dispatch(KundiBehaviorEvent event) {
    if (_disposed || _isDuplicate(event)) {
      return false;
    }

    final next = _reducer.reduce(state, event);
    if (identical(next, state)) {
      return false;
    }

    _cancelTimeout();
    state = next;
    _scheduleTimeout(next);
    return true;
  }

  bool _isDuplicate(KundiBehaviorEvent event) {
    final fingerprint = event.fingerprint?.trim();
    if (fingerprint == null || fingerprint.isEmpty) {
      return false;
    }

    final now = _clock.now();
    _pruneDedup(now);
    final key = '$fingerprint\u0000${event.id}';
    final seenAt = _dedup[key];
    if (seenAt != null && now.difference(seenAt) < _debounceWindow) {
      return true;
    }

    _dedup.remove(key);
    _dedup[key] = now;
    while (_dedup.length > _maxDedupEntries) {
      _dedup.remove(_dedup.keys.first);
    }
    return false;
  }

  void _pruneDedup(DateTime now) {
    final expired = <String>[];
    for (final entry in _dedup.entries) {
      final age = now.difference(entry.value);
      if (age.isNegative || age >= _debounceWindow) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _dedup.remove(key);
    }
  }

  void _scheduleTimeout(KundiBehaviorState current) {
    final deadline = current.expiresAt;
    if (_disposed || deadline == null) {
      return;
    }
    final sourceEventId = current.sourceEventId;
    _timeoutHandle = _clock.schedule(deadline, () {
      if (_disposed) {
        return;
      }
      _timeoutHandle = null;
      dispatch(
        KundiBehaviorEvent(
          type: KundiBehaviorEventType.timeoutElapsed,
          id: 'timeout:$sourceEventId',
          occurredAt: _clock.now(),
          targetStateEventId: sourceEventId,
        ),
      );
    });
  }

  void _cancelTimeout() {
    final handle = _timeoutHandle;
    if (handle == null) {
      return;
    }
    _clock.cancel(handle);
    _timeoutHandle = null;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelTimeout();
    _dedup.clear();
    super.dispose();
  }
}
