import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/auth/application/auth_controller.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/features/gamification/application/gamification_controller.dart';
import 'package:kundi_mobile/features/gamification/domain/gamification_entity.dart';
import 'package:kundi_mobile/features/gamification/domain/gamification_repository.dart';

void main() {
  test('concurrent start and resume record and present one unlock once',
      () async {
    final repository = _FakeGamificationRepository();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        gamificationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(gamificationControllerProvider.future);

    final controller = container.read(gamificationControllerProvider.notifier);
    final first = controller.recordDailyActivityAndClaim();
    final concurrent = controller.recordDailyActivityAndClaim();
    repository.activity.complete(_profile(pending: true));

    expect(await first, hasLength(1));
    expect(await concurrent, isEmpty);
    expect(repository.activityCalls, 1);
    expect(repository.acknowledgements, [
      ['activity_first_day'],
    ]);

    expect(await controller.recordDailyActivityAndClaim(), isEmpty);
    expect(repository.activityCalls, 1);
    expect(repository.acknowledgements, hasLength(1));
  });

  test('failed acknowledgement presents nothing and remains retryable',
      () async {
    final repository = _FakeGamificationRepository(failFirstAck: true);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        gamificationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(gamificationControllerProvider.future);

    final controller = container.read(gamificationControllerProvider.notifier);
    final first = controller.recordDailyActivityAndClaim();
    repository.activity.complete(_profile(pending: true));
    expect(await first, isEmpty);
    expect(await controller.recordDailyActivityAndClaim(), hasLength(1));
    expect(repository.activityCalls, 1);
    expect(repository.acknowledgements, hasLength(2));
  });
}

class _FakeAuthController extends AuthController {
  @override
  Future<AuthSession?> build() async => AuthSession(
        studentId: 'student',
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2030),
      );
}

class _FakeGamificationRepository implements GamificationRepository {
  _FakeGamificationRepository({this.failFirstAck = false});

  final bool failFirstAck;
  final Completer<GamificationProfile> activity = Completer();
  final List<List<String>> acknowledgements = [];
  int activityCalls = 0;

  @override
  Future<GamificationProfile> getProfile() async => _profile(pending: false);

  @override
  Future<GamificationProfile> recordActivity() {
    activityCalls++;
    return activity.future;
  }

  @override
  Future<void> acknowledge(List<String> achievementCodes) async {
    acknowledgements.add(List<String>.of(achievementCodes));
    if (failFirstAck && acknowledgements.length == 1) {
      throw StateError('response lost');
    }
  }
}

GamificationProfile _profile({required bool pending}) {
  final achievement = AchievementEntity(
    code: 'activity_first_day',
    category: 'activity',
    categoryTitle: const LocalizedGamificationText(
      ru: 'Активность',
      kk: 'Белсенділік',
    ),
    title: const LocalizedGamificationText(
      ru: 'Первый день',
      kk: 'Алғашқы күн',
    ),
    description:
        const LocalizedGamificationText(ru: 'Описание', kk: 'Сипаттама'),
    current: 1,
    target: 1,
    unlocked: true,
    unlockedAt: DateTime.utc(2026, 9, 9),
    seen: !pending,
  );
  return GamificationProfile(
    catalogVersion: 1,
    points: 30,
    level: 1,
    levelFloorPoints: 0,
    nextLevelPoints: 100,
    currentStreak: 1,
    longestStreak: 1,
    lastActiveDate: DateTime.utc(2026, 9, 9),
    achievementsUnlocked: 1,
    achievementsTotal: 13,
    achievements: [achievement],
    pendingUnlocks: pending ? [achievement] : const <AchievementEntity>[],
  );
}
