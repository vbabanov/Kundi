import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/auth/application/auth_controller.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/features/home_insight/application/home_insight_controller.dart';
import 'package:kundi_mobile/features/home_insight/domain/home_insight.dart';
import 'package:kundi_mobile/features/home_insight/domain/home_insight_repository.dart';
import 'package:kundi_mobile/features/profile/application/profile_controller.dart';
import 'package:kundi_mobile/features/profile/domain/profile_entity.dart';
import 'package:kundi_mobile/features/profile/domain/school_shift.dart';
import 'package:kundi_mobile/features/settings/application/settings_controller.dart';
import 'package:kundi_mobile/features/settings/domain/settings_entity.dart';

void main() {
  test('first read is local and a server result replaces it asynchronously',
      () async {
    final repository = _CompletingRepository();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_AuthenticatedController.new),
        settingsControllerProvider.overrideWith(_KazakhSettingsController.new),
        profileControllerProvider.overrideWith(_PrimaryProfileController.new),
        homeInsightRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await Future.wait([
      container.read(authControllerProvider.future),
      container.read(settingsControllerProvider.future),
      container.read(profileControllerProvider.future),
    ]);

    final first = container.read(homeInsightControllerProvider);

    expect(first.isLocalFallback, isTrue);
    expect(first.locale, 'kk');
    expect(first.gradeBand, HomeInsightGradeBand.primary);
    await Future<void>.delayed(Duration.zero);
    expect(repository.locale, 'kk');

    repository.completer.complete(const HomeInsight(
      text: 'Серверден келген кеңес.',
      kind: HomeInsightKind.studyTip,
      locale: 'kk',
      contentId: 'server_tip_v1',
      catalogVersion: 1,
      gradeBand: HomeInsightGradeBand.primary,
      rephrased: false,
      isLocalFallback: false,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(homeInsightControllerProvider).text,
        'Серверден келген кеңес.');
  });
}

class _CompletingRepository implements HomeInsightRepository {
  final completer = Completer<HomeInsight>();
  String locale = '';

  @override
  Future<HomeInsight> getInsight({required String locale}) {
    this.locale = locale;
    return completer.future;
  }
}

class _AuthenticatedController extends AuthController {
  @override
  Future<AuthSession?> build() async => AuthSession(
        studentId: 'student',
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2026, 10),
      );
}

class _KazakhSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings(
        language: AppLanguage.kk,
      );
}

class _PrimaryProfileController extends ProfileController {
  @override
  Future<ProfileEntity?> build() async => const ProfileEntity(
        readMode: 'v2',
        providerIdentity: ProviderIdentityProfileSection(
          studentId: 'student',
          provider: 'kundelik',
          providerAccountRef: 'account',
          providerPersonId: 'person',
          providerSchoolId: 'school',
          providerGroupId: 'group',
          studentFullName: 'Оқушы',
          schoolName: 'Мектеп',
          classLabel: '2А',
          classTeacherFullName: 'Мұғалім',
          gradeLevel: 2,
        ),
        localAppProfile: null,
        automaticShift: SchoolShift.first,
      );
}
