import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/profile/application/profile_controller.dart';
import 'package:kundi_mobile/features/profile/domain/profile_entity.dart';
import 'package:kundi_mobile/features/profile/domain/profile_repository.dart';
import 'package:kundi_mobile/features/profile/presentation/profile_page.dart';

void main() {
  testWidgets('renders v2 provider and local sections', (tester) async {
    final repository = _FakeProfileRepository([
      _profileEntityWithLocal(),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Профиль'), findsOneWidget);
    expect(find.textContaining('Artem Bayurzan'), findsOneWidget);
    expect(find.textContaining('School 1'), findsOneWidget);
    expect(find.text('Смена'), findsOneWidget);
    expect(find.text('Номер родителя 1'), findsOneWidget);
    expect(find.text('Номер родителя 2 (опционально)'), findsOneWidget);
  });

  testWidgets(
      'renders local profile empty-state when local_app_profile is null',
      (tester) async {
    final repository = _FakeProfileRepository([
      _profileEntityProviderOnly(),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Provider Only'), findsOneWidget);
    expect(find.text('Смена'), findsOneWidget);
    expect(find.text('Номер родителя 1'), findsOneWidget);
  });

  testWidgets('golden preview for profile page v2 split', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _FakeProfileRepository([
      _profileEntityWithLocal(),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ProfilePage),
      matchesGoldenFile('goldens/profile_page_v2_split.png'),
    );
  });
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this._responses);

  final List<ProfileEntity?> _responses;
  int _index = 0;

  @override
  Future<ProfileEntity?> get() async {
    if (_responses.isEmpty) {
      return null;
    }
    final current =
        _index < _responses.length ? _responses[_index] : _responses.last;
    _index += 1;
    return current;
  }

  @override
  Future<void> saveLocalAppProfile({
    required int shift,
    required String parentPhone1,
    required String parentPhone2,
  }) async {}
}

ProfileEntity _profileEntityWithLocal() {
  return const ProfileEntity(
    readMode: 'v2',
    providerIdentity: ProviderIdentityProfileSection(
      studentId: 'student-1',
      provider: 'kundelik',
      providerAccountRef: 'acc-1',
      providerPersonId: 'person-1',
      providerSchoolId: 'school-1',
      providerGroupId: 'group-1',
      studentFullName: 'Artem Bayurzan',
      schoolName: 'School 1',
      classLabel: '7Zh',
      classTeacherFullName: 'Teacher Name',
      gradeLevel: 7,
    ),
    localAppProfile: LocalAppProfileSection(
      shift: 1,
      parentPhone1: '+77010000001',
      parentPhone2: '+77010000002',
    ),
  );
}

ProfileEntity _profileEntityProviderOnly() {
  return const ProfileEntity(
    readMode: 'v2',
    providerIdentity: ProviderIdentityProfileSection(
      studentId: 'student-1',
      provider: 'kundelik',
      providerAccountRef: 'acc-1',
      providerPersonId: 'person-1',
      providerSchoolId: 'school-1',
      providerGroupId: 'group-1',
      studentFullName: 'Provider Only',
      schoolName: 'School 1',
      classLabel: '7Zh',
      classTeacherFullName: 'Teacher Name',
      gradeLevel: 7,
    ),
    localAppProfile: null,
  );
}
