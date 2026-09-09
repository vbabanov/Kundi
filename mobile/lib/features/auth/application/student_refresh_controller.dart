import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../grades/application/grades_controller.dart';
import '../../gamification/application/gamification_controller.dart';
import '../../homework/application/homework_controller.dart';
import '../../lessons/application/lessons_controller.dart';
import '../../profile/application/profile_controller.dart';
import '../../summary/application/summary_controller.dart';
import '../data/auth_repository_impl.dart';
import 'auth_controller.dart';

class StudentRefreshState {
  const StudentRefreshState({
    this.isRefreshing = false,
    this.lastResult,
    this.error,
  });

  final bool isRefreshing;
  final AuthenticatedStudentRefreshResult? lastResult;
  final Object? error;
}

final studentRefreshControllerProvider =
    NotifierProvider<StudentRefreshController, StudentRefreshState>(
      StudentRefreshController.new,
    );

/// Owns the only user-initiated provider refresh transaction. Page gestures
/// join [_inFlight], then every screen projection reloads from the one active
/// cache snapshot published by the repository.
class StudentRefreshController extends Notifier<StudentRefreshState> {
  Future<AuthenticatedStudentRefreshResult>? _inFlight;

  @override
  StudentRefreshState build() => const StudentRefreshState();

  Future<AuthenticatedStudentRefreshResult> refresh() {
    final active = _inFlight;
    if (active != null) {
      return active;
    }
    final future = _run();
    _inFlight = future;
    void clearInFlight() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }

    unawaited(
      future.then<void>(
        (_) => clearInFlight(),
        onError: (Object _, StackTrace __) => clearInFlight(),
      ),
    );
    return future;
  }

  Future<AuthenticatedStudentRefreshResult> _run() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw StateError('Authenticated student refresh requires a session.');
    }
    state = StudentRefreshState(
      isRefreshing: true,
      lastResult: state.lastResult,
    );
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .refreshAuthenticatedStudent(session);
      ref
          .read(authControllerProvider.notifier)
          .adoptRefreshedSession(result.session);
      await Future.wait<void>([
        ref.read(lessonsControllerProvider.notifier).reloadFromCache(),
        ref.read(homeworkControllerProvider.notifier).reloadFromCache(),
        ref.read(gradesControllerProvider.notifier).reloadFromCache(),
        ref.read(profileControllerProvider.notifier).reloadFromCache(),
        ref.read(summaryControllerProvider.notifier).reloadFromCache(),
        ref
            .read(gamificationControllerProvider.notifier)
            .refresh()
            .then<void>((_) {}),
      ]);
      debugPrint(
        '[KUNDI_REFRESH] trace_id=${result.traceId} '
        'snapshot_at=${result.snapshotAt} controllers=6',
      );
      state = StudentRefreshState(lastResult: result);
      return result;
    } catch (error) {
      state = StudentRefreshState(lastResult: state.lastResult, error: error);
      rethrow;
    }
  }
}
