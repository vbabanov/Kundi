import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/application/profile_controller.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/settings_entity.dart';
import '../data/home_insight_repository_impl.dart';
import '../domain/home_insight.dart';
import '../domain/home_insight_repository.dart';

final homeInsightRepositoryProvider = Provider<HomeInsightRepository>((ref) {
  return HomeInsightRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    readSession: () => ref.read(authControllerProvider).valueOrNull,
  );
});

final homeInsightControllerProvider =
    NotifierProvider<HomeInsightController, HomeInsight>(
  HomeInsightController.new,
);

class HomeInsightController extends Notifier<HomeInsight> {
  String _activeKey = '';
  final Map<String, Future<void>> _requests = <String, Future<void>>{};
  final Map<String, HomeInsight> _memory = <String, HomeInsight>{};

  @override
  HomeInsight build() {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final settings = ref.watch(settingsControllerProvider).valueOrNull ??
        const AppSettings();
    final gradeLevel = ref
            .watch(profileControllerProvider)
            .valueOrNull
            ?.providerIdentity
            ?.gradeLevel ??
        5;
    final locale = settings.language == AppLanguage.kk ? 'kk' : 'ru';
    final now = DateTime.now();
    final key = [
      session?.studentId ?? 'guest',
      locale,
      gradeBandFor(gradeLevel).name,
      now.year,
      now.month,
      now.day,
    ].join('|');
    _activeKey = key;
    final fallback = HomeInsight.localFallback(
      locale: locale,
      gradeLevel: gradeLevel,
    );
    final cached = _memory[key];
    if (session != null && cached == null && !_requests.containsKey(key)) {
      unawaited(Future<void>.microtask(() => _load(key, locale)));
    }
    return cached ?? fallback;
  }

  Future<void> refresh() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;
    final settings =
        ref.read(settingsControllerProvider).valueOrNull ?? const AppSettings();
    final gradeLevel = ref
            .read(profileControllerProvider)
            .valueOrNull
            ?.providerIdentity
            ?.gradeLevel ??
        5;
    final locale = settings.language == AppLanguage.kk ? 'kk' : 'ru';
    final now = DateTime.now();
    final key = [
      session.studentId,
      locale,
      gradeBandFor(gradeLevel).name,
      now.year,
      now.month,
      now.day,
    ].join('|');
    if (_activeKey != key) {
      _activeKey = key;
      state = _memory[key] ??
          HomeInsight.localFallback(
            locale: locale,
            gradeLevel: gradeLevel,
          );
    }
    await _load(key, locale);
  }

  Future<void> _load(String key, String locale) async {
    final running = _requests[key];
    if (running != null) return running;
    final request = _loadOnce(key, locale);
    _requests[key] = request;
    try {
      await request;
    } finally {
      if (identical(_requests[key], request)) _requests.remove(key);
    }
  }

  Future<void> _loadOnce(String key, String locale) async {
    try {
      final insight = await ref
          .read(homeInsightRepositoryProvider)
          .getInsight(locale: locale);
      if (!_memory.containsKey(key) && _memory.length >= 16) {
        _memory.remove(_memory.keys.first);
      }
      _memory[key] = insight;
      if (_activeKey == key) state = insight;
    } on Object {
      // The synchronous local copy remains visible. A daily insight must never
      // turn Home into a loading or error screen.
    }
  }
}
