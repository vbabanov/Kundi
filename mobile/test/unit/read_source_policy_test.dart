import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/network/read_source_policy.dart';

void main() {
  test('v2 policy falls back only on transport failures', () {
    const policy =
        ReadSourcePolicy(useTypedV2Read: true, enableV2ParityShadow: false);
    expect(policy.initialMode(), ReadSourceMode.v2);

    final transportError = DioException(
      requestOptions: RequestOptions(path: '/v2/profile'),
      type: DioExceptionType.connectionTimeout,
    );
    expect(
        policy.isTransportFailureEligibleForFallback(transportError), isTrue);

    final schemaError = const FormatException('schema mismatch');
    expect(policy.isTransportFailureEligibleForFallback(schemaError), isFalse);

    final authError = DioException(
      requestOptions: RequestOptions(path: '/v2/profile'),
      response: Response(
        requestOptions: RequestOptions(path: '/v2/profile'),
        statusCode: 401,
      ),
      type: DioExceptionType.badResponse,
    );
    expect(policy.isTransportFailureEligibleForFallback(authError), isFalse);
  });

  test('v1 policy starts in v1 mode', () {
    const policy =
        ReadSourcePolicy(useTypedV2Read: false, enableV2ParityShadow: false);
    expect(policy.initialMode(), ReadSourceMode.v1);
  });

  test('cohort percent enables deterministic partial rollout', () {
    const policy = ReadSourcePolicy(
      useTypedV2Read: true,
      enableV2ParityShadow: false,
      typedV2CohortPercent: 2,
    );
    final decisionA = policy.typedV2Decision(studentId: 'student-a');
    final decisionB = policy.typedV2Decision(studentId: 'student-a');
    expect(decisionA.mode, decisionB.mode);
    expect(decisionA.bucket, decisionB.bucket);
    expect(decisionA.reason, anyOf('cohort_percent_in', 'cohort_percent_out'));
    expect(decisionA.percent, 2);
  });

  test('allowlist and denylist are explicit and reversible controls', () {
    const policy = ReadSourcePolicy(
      useTypedV2Read: true,
      enableV2ParityShadow: false,
      typedV2CohortPercent: 2,
      typedV2CohortAllowlist: 'student-allow',
      typedV2CohortDenylist: 'student-deny',
    );
    final allowed = policy.typedV2Decision(studentId: 'student-allow');
    final denied = policy.typedV2Decision(studentId: 'student-deny');
    expect(allowed.mode, ReadSourceMode.v2);
    expect(allowed.reason, 'allowlist');
    expect(denied.mode, ReadSourceMode.v1);
    expect(denied.reason, 'denylist');
  });

  test('force flags override cohort and global settings', () {
    const forceV1 = ReadSourcePolicy(
      useTypedV2Read: true,
      enableV2ParityShadow: false,
      forceLegacyV1Read: true,
      typedV2CohortPercent: 100,
    );
    const forceV2 = ReadSourcePolicy(
      useTypedV2Read: false,
      enableV2ParityShadow: false,
      forceTypedV2Read: true,
    );
    expect(
      forceV1.typedV2Decision(studentId: 'x').reason,
      'force_v1',
    );
    expect(
      forceV1.typedV2Decision(studentId: 'x').mode,
      ReadSourceMode.v1,
    );
    expect(
      forceV2.typedV2Decision(studentId: 'x').reason,
      'force_v2',
    );
    expect(
      forceV2.typedV2Decision(studentId: 'x').mode,
      ReadSourceMode.v2,
    );
  });

  test('fallback reason codes are stable', () {
    const policy =
        ReadSourcePolicy(useTypedV2Read: true, enableV2ParityShadow: false);
    final schemaError = const FormatException('schema');
    expect(policy.fallbackReasonCode(schemaError), 'schema_mismatch');
  });

  test('hold triggers: degraded spike source is transport-only fallback', () {
    const policy =
        ReadSourcePolicy(useTypedV2Read: true, enableV2ParityShadow: false);
    final degraded503 = DioException(
      requestOptions: RequestOptions(path: '/v2/results'),
      response: Response(
        requestOptions: RequestOptions(path: '/v2/results'),
        statusCode: 503,
      ),
      type: DioExceptionType.badResponse,
    );
    expect(policy.fallbackReasonCode(degraded503), 'transport_failure');
    expect(policy.isTransportFailureEligibleForFallback(degraded503), isTrue);
  });

  test('hold triggers: auth/session and contract errors never fallback', () {
    const policy =
        ReadSourcePolicy(useTypedV2Read: true, enableV2ParityShadow: false);
    final auth401 = DioException(
      requestOptions: RequestOptions(path: '/v2/profile'),
      response: Response(
        requestOptions: RequestOptions(path: '/v2/profile'),
        statusCode: 401,
      ),
      type: DioExceptionType.badResponse,
    );
    final contract404 = DioException(
      requestOptions: RequestOptions(path: '/v2/profile'),
      response: Response(
        requestOptions: RequestOptions(path: '/v2/profile'),
        statusCode: 404,
      ),
      type: DioExceptionType.badResponse,
    );
    expect(policy.fallbackReasonCode(auth401), 'auth_or_session');
    expect(policy.fallbackReasonCode(contract404), 'domain_or_contract');
    expect(policy.isTransportFailureEligibleForFallback(auth401), isFalse);
    expect(policy.isTransportFailureEligibleForFallback(contract404), isFalse);
  });
}
