import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/app_database.dart';
import 'package:kundi_mobile/core/db/canonical_cache_store.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/features/profile/data/profile_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.setTestDbNameOverride('kundi_mobile_profile_repo_v2.db');
  });

  tearDownAll(() {
    AppDatabase.setTestDbNameOverride(null);
  });

  setUp(() async {
    final db = await AppDatabase.open();
    await db.delete('canonical_provider_identity_cache_v2');
    await db.delete('canonical_local_app_profile_cache_v2');
    await db.delete('canonical_read_mode_metadata');
    await db.delete('canonical_profile_cache');
  });

  test('reads provider_identity and local_app_profile as separate v2 sections',
      () async {
    final db = await AppDatabase.open();
    final store = CanonicalCacheStore();
    final repository = ProfileRepositoryImpl(
      store,
      _NoopApiClient(),
      () => null,
    );
    const studentId = 'student-42';
    const provider = 'kundelik';
    const windowKey = 'kundelik:2026-03-01:2026-03-31';
    const snapshotAt = '2026-04-01T08:00:00Z';
    const scopedWindowKey = '$studentId:$provider:$windowKey';
    final now = DateTime.now().toUtc().toIso8601String();

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: windowKey,
      snapshotAt: snapshotAt,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-profile-v2',
    );

    await db.insert(
      'canonical_provider_identity_cache_v2',
      {
        'student_id': studentId,
        'provider': provider,
        'provider_account_ref': 'acc-1',
        'provider_person_id': 'person-1',
        'provider_school_id': 'school-1',
        'provider_group_id': 'group-1',
        'student_full_name': 'Artem Bayurzan',
        'school_name': 'Kundelik School',
        'class_label': '7Zh',
        'class_teacher_full_name': 'Teacher Name',
        'window_key': scopedWindowKey,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'canonical_local_app_profile_cache_v2',
      {
        'profile_scope': 'local:$studentId:$provider',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-1',
        'shift': 2,
        'parent_phone_1': '+77010000001',
        'parent_phone_2': '+77010000002',
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final profile = await repository.get();

    expect(profile, isNotNull);
    expect(profile!.readMode, 'v2');
    expect(profile.providerIdentity, isNotNull);
    expect(profile.localAppProfile, isNotNull);
    expect(profile.providerIdentity!.studentId, studentId);
    expect(profile.providerIdentity!.provider, provider);
    expect(profile.providerIdentity!.studentFullName, 'Artem Bayurzan');
    expect(profile.providerIdentity!.schoolName, 'Kundelik School');
    expect(profile.providerIdentity!.classLabel, '7Zh');
    expect(profile.providerIdentity!.classTeacherFullName, 'Teacher Name');
    expect(profile.localAppProfile!.shift, 2);
    expect(profile.localAppProfile!.parentPhone1, '+77010000001');
    expect(profile.localAppProfile!.parentPhone2, '+77010000002');
  });

  test('provider section remains available when local_app_profile is missing',
      () async {
    final db = await AppDatabase.open();
    final store = CanonicalCacheStore();
    final repository = ProfileRepositoryImpl(
      store,
      _NoopApiClient(),
      () => null,
    );
    const studentId = 'student-55';
    const provider = 'kundelik';
    const windowKey = 'kundelik:2026-03-10:2026-03-20';
    const snapshotAt = '2026-04-01T11:00:00Z';
    const scopedWindowKey = '$studentId:$provider:$windowKey';
    final now = DateTime.now().toUtc().toIso8601String();

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: windowKey,
      snapshotAt: snapshotAt,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-profile-v2-provider-only',
    );

    await db.insert(
      'canonical_provider_identity_cache_v2',
      {
        'student_id': studentId,
        'provider': provider,
        'provider_account_ref': 'acc-2',
        'provider_person_id': 'person-2',
        'provider_school_id': 'school-2',
        'provider_group_id': 'group-2',
        'student_full_name': 'Provider Only',
        'school_name': 'School 2',
        'class_label': '8A',
        'class_teacher_full_name': 'Teacher 2',
        'window_key': scopedWindowKey,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final profile = await repository.get();

    expect(profile, isNotNull);
    expect(profile!.readMode, 'v2');
    expect(profile.providerIdentity, isNotNull);
    expect(profile.providerIdentity!.studentFullName, 'Provider Only');
    expect(profile.localAppProfile, isNull);
  });

  test('falls back to legacy profile cache when active read mode is v1',
      () async {
    final db = await AppDatabase.open();
    final store = CanonicalCacheStore();
    final repository = ProfileRepositoryImpl(
      store,
      _NoopApiClient(),
      () => null,
    );
    final now = DateTime.now().toUtc().toIso8601String();

    await store.setReadMode(
      studentId: 'student-v1',
      provider: 'kundelik',
      mode: 'v1',
      windowKey: 'kundelik:v1',
      snapshotAt: '2026-04-01T12:00:00Z',
      refreshMode: 'v1',
      refreshStatus: 'success',
      traceId: 'trace-profile-v1',
    );
    await db.insert(
      'canonical_profile_cache',
      {
        'student_id': 'student-v1',
        'first_name': 'Legacy',
        'last_name': 'Student',
        'grade_level': 9,
        'class_label': '9B',
        'school_name': 'Legacy School',
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final profile = await repository.get();

    expect(profile, isNotNull);
    expect(profile!.readMode, 'v1');
    expect(profile.providerIdentity, isNotNull);
    expect(profile.providerIdentity!.provider, 'kundelik');
    expect(profile.providerIdentity!.studentFullName, 'Legacy Student');
    expect(profile.providerIdentity!.schoolName, 'Legacy School');
    expect(profile.providerIdentity!.classLabel, '9B');
    expect(profile.providerIdentity!.gradeLevel, 9);
    expect(profile.localAppProfile, isNull);
  });
}

class _NoopApiClient extends ApiClient {
  _NoopApiClient() : super(baseUrl: 'http://127.0.0.1:1');
}
