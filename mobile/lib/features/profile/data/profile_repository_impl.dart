import 'package:dio/dio.dart';

import '../../../core/db/canonical_cache_store.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_session.dart';
import '../domain/profile_entity.dart';
import '../domain/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(
    this._cacheStore,
    this._apiClient,
    this._readSession,
  );

  final CanonicalCacheStore _cacheStore;
  final ApiClient _apiClient;
  final AuthSession? Function() _readSession;

  @override
  Future<ProfileEntity?> get() async {
    final context = await _cacheStore.getActiveReadContext();
    if (context != null && context.hasCompleteV2Scope) {
      final providerIdentity =
          await _cacheStore.getV2ProviderIdentity(context: context);
      final localAppProfile =
          await _cacheStore.getV2LocalAppProfile(context: context);
      final providerSection = providerIdentity == null
          ? null
          : _mapV2ProviderIdentity(
              studentId: context.studentId,
              provider: context.provider,
              row: providerIdentity,
            );
      final localSection = localAppProfile == null
          ? null
          : _mapV2LocalAppProfile(localAppProfile);
      if (providerSection == null && localSection == null) {
        return null;
      }
      return ProfileEntity(
        readMode: 'v2',
        providerIdentity: providerSection,
        localAppProfile: localSection,
      );
    }

    final row = await _cacheStore.getProfile();
    if (row == null) {
      return null;
    }
    final providerSection = _mapV1ProviderIdentity(
      studentId: (row['student_id'] ?? '').toString(),
      provider: context?.provider ?? '',
      row: row,
    );
    return ProfileEntity(
      readMode: 'v1',
      providerIdentity: providerSection,
      localAppProfile: null,
    );
  }

  @override
  Future<void> saveLocalAppProfile({
    required int shift,
    required String parentPhone1,
    required String parentPhone2,
  }) async {
    final session = _readSession();
    if (session == null || session.accessToken.trim().isEmpty) {
      throw const AppException(
        'not_authenticated',
        'Please login again before updating profile.',
      );
    }
    final response = await _apiClient.put(
      '/v1/profile/local',
      options: Options(headers: {
        'Authorization': 'Bearer ${session.accessToken}',
      }),
      data: {
        'shift': shift,
        'parent_phone_1': parentPhone1,
        'parent_phone_2': parentPhone2,
      },
    );
    if (response.statusCode != 200) {
      throw const AppException(
        'profile_update_failed',
        'Unable to update profile now. Try again.',
      );
    }
    final payload = response.data is Map
        ? Map<String, dynamic>.from(
            (response.data as Map)['data'] as Map? ?? response.data as Map,
          )
        : <String, dynamic>{};
    final resolvedShift =
        int.tryParse((payload['shift'] ?? '').toString()) ?? shift;
    final resolvedPhone1 =
        (payload['parent_phone_1'] ?? parentPhone1).toString();
    final resolvedPhone2 =
        (payload['parent_phone_2'] ?? parentPhone2).toString();

    final context = await _cacheStore.getActiveReadContext();
    final provider = context?.provider.trim().isNotEmpty == true
        ? context!.provider.trim()
        : 'kundelik';
    String providerPersonId = '';
    if (context != null && context.hasCompleteV2Scope) {
      final providerIdentity =
          await _cacheStore.getV2ProviderIdentity(context: context);
      providerPersonId =
          (providerIdentity?['provider_person_id'] ?? '').toString();
    }
    await _cacheStore.upsertLocalAppProfile(
      studentId: session.studentId,
      provider: provider,
      providerPersonId: providerPersonId,
      shift: resolvedShift,
      parentPhone1: resolvedPhone1,
      parentPhone2: resolvedPhone2,
    );
  }

  ProviderIdentityProfileSection _mapV2ProviderIdentity({
    required String studentId,
    required String provider,
    required Map<String, dynamic> row,
  }) {
    final classLabel = (row['class_label'] ?? '').toString();
    return ProviderIdentityProfileSection(
      studentId: studentId,
      provider: provider,
      providerAccountRef: (row['provider_account_ref'] ?? '').toString(),
      providerPersonId: (row['provider_person_id'] ?? '').toString(),
      providerSchoolId: (row['provider_school_id'] ?? '').toString(),
      providerGroupId: (row['provider_group_id'] ?? '').toString(),
      studentFullName: (row['student_full_name'] ?? '').toString(),
      schoolName: (row['school_name'] ?? '').toString(),
      classLabel: classLabel,
      classTeacherFullName: (row['class_teacher_full_name'] ?? '').toString(),
      gradeLevel: _extractGradeLevel(classLabel),
      studentFirstName: resolveStudentFirstName(
        explicitFirstName: '',
        fullName: (row['student_full_name'] ?? '').toString(),
      ),
    );
  }

  LocalAppProfileSection _mapV2LocalAppProfile(Map<String, dynamic> row) {
    return LocalAppProfileSection(
      shift: int.tryParse((row['shift'] ?? '').toString()),
      parentPhone1: (row['parent_phone_1'] ?? '').toString(),
      parentPhone2: (row['parent_phone_2'] ?? '').toString(),
    );
  }

  ProviderIdentityProfileSection _mapV1ProviderIdentity({
    required String studentId,
    required String provider,
    required Map<String, dynamic> row,
  }) {
    final firstName = (row['first_name'] ?? '').toString();
    final lastName = (row['last_name'] ?? '').toString();
    final classLabel = (row['class_label'] ?? '').toString();
    final schoolName = (row['school_name'] ?? '').toString();
    final fallbackProvider = provider.trim().isEmpty ? 'kundelik' : provider;
    return ProviderIdentityProfileSection(
      studentId: studentId,
      provider: fallbackProvider,
      providerAccountRef: '',
      providerPersonId: '',
      providerSchoolId: '',
      providerGroupId: '',
      studentFullName: '$firstName $lastName'.trim(),
      schoolName: schoolName,
      classLabel: classLabel,
      classTeacherFullName: '',
      gradeLevel: int.tryParse((row['grade_level'] ?? '').toString()) ??
          _extractGradeLevel(classLabel),
      studentFirstName: resolveStudentFirstName(
        explicitFirstName: firstName,
        fullName: '$firstName $lastName',
      ),
    );
  }

  int _extractGradeLevel(String classLabel) {
    final match = RegExp(r'\d+').firstMatch(classLabel);
    if (match == null) {
      return 1;
    }
    return int.tryParse(match.group(0) ?? '') ?? 1;
  }
}
