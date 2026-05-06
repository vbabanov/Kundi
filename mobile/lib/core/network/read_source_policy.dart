import 'package:dio/dio.dart';

enum ReadSourceMode {
  v1,
  v2,
}

class TypedV2CohortDecision {
  const TypedV2CohortDecision({
    required this.mode,
    required this.reason,
    required this.studentId,
    this.bucket,
    this.percent,
  });

  final ReadSourceMode mode;
  final String reason;
  final String studentId;
  final int? bucket;
  final int? percent;
}

enum FallbackDecision {
  allowTransportFallback,
  denySchemaMismatch,
  denyAuthOrSession,
  denyDomainOrContract,
  denyOther,
}

class ReadSourcePolicy {
  const ReadSourcePolicy({
    required this.useTypedV2Read,
    required this.enableV2ParityShadow,
    this.forceTypedV2Read = false,
    this.forceLegacyV1Read = false,
    this.typedV2CohortPercent = -1,
    this.typedV2CohortAllowlist = '',
    this.typedV2CohortDenylist = '',
  });

  final bool useTypedV2Read;
  final bool enableV2ParityShadow;
  final bool forceTypedV2Read;
  final bool forceLegacyV1Read;
  final int typedV2CohortPercent;
  final String typedV2CohortAllowlist;
  final String typedV2CohortDenylist;

  ReadSourceMode initialMode({String studentId = ''}) {
    return typedV2Decision(studentId: studentId).mode;
  }

  TypedV2CohortDecision typedV2Decision({required String studentId}) {
    final normalizedStudentId = _normalizeStudentId(studentId);
    final effectivePercent = _normalizePercent(typedV2CohortPercent);

    if (forceLegacyV1Read) {
      return TypedV2CohortDecision(
        mode: ReadSourceMode.v1,
        reason: 'force_v1',
        studentId: normalizedStudentId,
      );
    }
    if (forceTypedV2Read) {
      return TypedV2CohortDecision(
        mode: ReadSourceMode.v2,
        reason: 'force_v2',
        studentId: normalizedStudentId,
      );
    }
    if (!useTypedV2Read) {
      return TypedV2CohortDecision(
        mode: ReadSourceMode.v1,
        reason: 'global_v2_disabled',
        studentId: normalizedStudentId,
      );
    }

    final denylist = _parseStudentSet(typedV2CohortDenylist);
    if (normalizedStudentId.isNotEmpty &&
        denylist.contains(normalizedStudentId)) {
      return TypedV2CohortDecision(
        mode: ReadSourceMode.v1,
        reason: 'denylist',
        studentId: normalizedStudentId,
      );
    }

    final allowlist = _parseStudentSet(typedV2CohortAllowlist);
    if (normalizedStudentId.isNotEmpty &&
        allowlist.contains(normalizedStudentId)) {
      return TypedV2CohortDecision(
        mode: ReadSourceMode.v2,
        reason: 'allowlist',
        studentId: normalizedStudentId,
      );
    }

    if (effectivePercent != null) {
      if (normalizedStudentId.isEmpty) {
        return TypedV2CohortDecision(
          mode: ReadSourceMode.v1,
          reason: 'cohort_missing_student_id',
          studentId: normalizedStudentId,
          percent: effectivePercent,
        );
      }
      final bucket = _stableBucket(normalizedStudentId);
      final inCohort = bucket < effectivePercent;
      return TypedV2CohortDecision(
        mode: inCohort ? ReadSourceMode.v2 : ReadSourceMode.v1,
        reason: inCohort ? 'cohort_percent_in' : 'cohort_percent_out',
        studentId: normalizedStudentId,
        bucket: bucket,
        percent: effectivePercent,
      );
    }

    return TypedV2CohortDecision(
      mode: ReadSourceMode.v2,
      reason: 'global_v2_enabled',
      studentId: normalizedStudentId,
    );
  }

  bool isTransportFailureEligibleForFallback(Object error) {
    return fallbackDecision(error) == FallbackDecision.allowTransportFallback;
  }

  FallbackDecision fallbackDecision(Object error) {
    if (error is FormatException) {
      return FallbackDecision.denySchemaMismatch;
    }
    if (error is! DioException) {
      return FallbackDecision.denyOther;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 401 || status == 403) {
      return FallbackDecision.denyAuthOrSession;
    }
    if (status == 400 || status == 404 || status == 409 || status == 422) {
      return FallbackDecision.denyDomainOrContract;
    }
    if (status == 429 || status == 502 || status == 503 || status == 504) {
      return FallbackDecision.allowTransportFallback;
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return FallbackDecision.allowTransportFallback;
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return status == 0
            ? FallbackDecision.allowTransportFallback
            : FallbackDecision.denyOther;
    }
  }

  String fallbackReasonCode(Object error) {
    switch (fallbackDecision(error)) {
      case FallbackDecision.allowTransportFallback:
        return 'transport_failure';
      case FallbackDecision.denySchemaMismatch:
        return 'schema_mismatch';
      case FallbackDecision.denyAuthOrSession:
        return 'auth_or_session';
      case FallbackDecision.denyDomainOrContract:
        return 'domain_or_contract';
      case FallbackDecision.denyOther:
        return 'other';
    }
  }

  int _stableBucket(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash % 100;
  }

  Set<String> _parseStudentSet(String raw) {
    return raw
        .split(',')
        .map(_normalizeStudentId)
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  String _normalizeStudentId(String studentId) {
    return studentId.trim().toLowerCase();
  }

  int? _normalizePercent(int rawPercent) {
    if (rawPercent < 0) {
      return null;
    }
    if (rawPercent > 100) {
      return 100;
    }
    return rawPercent;
  }
}
