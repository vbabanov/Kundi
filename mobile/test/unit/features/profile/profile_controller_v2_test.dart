import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/profile/application/profile_controller.dart';
import 'package:kundi_mobile/features/profile/domain/profile_entity.dart';
import 'package:kundi_mobile/features/profile/domain/profile_repository.dart';

void main() {
  test('controller exposes split profile sections from repository', () async {
    final repository = _FakeProfileRepository([
      _profileEntityWithLocal(),
    ]);
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final profile = await container.read(profileControllerProvider.future);

    expect(profile, isNotNull);
    expect(profile!.readMode, 'v2');
    expect(profile.providerIdentity, isNotNull);
    expect(profile.localAppProfile, isNotNull);
    expect(profile.providerIdentity!.providerPersonId, 'person-1');
    expect(profile.localAppProfile!.shift, 1);
    expect(repository.calls, 1);
  });

  test(
      'refreshFromCache updates state and keeps provider section without local',
      () async {
    final repository = _FakeProfileRepository([
      _profileEntityWithLocal(),
      _profileEntityProviderOnly(),
    ]);
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(profileControllerProvider.future);
    await container.read(profileControllerProvider.notifier).refreshFromCache();
    final state = container.read(profileControllerProvider);

    expect(repository.calls, 2);
    expect(state.hasValue, isTrue);
    final profile = state.value!;
    expect(profile.readMode, 'v2');
    expect(profile.providerIdentity, isNotNull);
    expect(profile.providerIdentity!.studentFullName, 'Provider Only');
    expect(profile.localAppProfile, isNull);
  });
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this._responses);

  final List<ProfileEntity?> _responses;
  int calls = 0;

  @override
  Future<ProfileEntity?> get() async {
    final index = calls < _responses.length ? calls : _responses.length - 1;
    calls += 1;
    if (index < 0) {
      return null;
    }
    return _responses[index];
  }

  @override
  Future<void> saveLocalAppProfile({
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
      classLabel: '7Ж',
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
      classLabel: '7Ж',
      classTeacherFullName: 'Teacher Name',
      gradeLevel: 7,
    ),
    localAppProfile: null,
  );
}
