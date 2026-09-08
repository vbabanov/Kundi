import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/db/canonical_cache_store.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/read_source_policy.dart';
import '../../../core/network/v2_read_models.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../runtimes/connector_runtime/connector_runtime.dart';
import '../../../runtimes/connector_runtime/contracts/models.dart';
import '../../../runtimes/connector_runtime/sync_queue/sync_orchestrator.dart';
import '../../../runtimes/connector_runtime/sync_queue/sync_queue_service.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';
import 'academic_year_window.dart';
import 'parity_shadow.dart';
import 'refresh_run_gate.dart';
import 'typed_v2_runtime_gate.dart';

enum _RefreshCycleStatus {
  success,
  degraded,
  failed,
}

class _RefreshCycleResult {
  const _RefreshCycleResult({
    required this.status,
    required this.mode,
    required this.provider,
    required this.traceId,
    this.fallbackReason = '',
    this.errorCode = '',
    this.errorMessage = '',
  });

  final _RefreshCycleStatus status;
  final String mode;
  final String provider;
  final String traceId;
  final String fallbackReason;
  final String errorCode;
  final String errorMessage;
}

class AuthenticatedStudentRefreshResult {
  const AuthenticatedStudentRefreshResult({
    required this.session,
    required this.traceId,
    required this.provider,
    required this.readMode,
    required this.windowKey,
    required this.snapshotAt,
  });

  final AuthSession session;
  final String traceId;
  final String provider;
  final String readMode;
  final String windowKey;
  final String snapshotAt;
}

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
    required ConnectorRuntime connectorRuntime,
    required CanonicalCacheStore canonicalCacheStore,
    required SyncQueueService syncQueueService,
    required SyncOrchestrator syncOrchestrator,
    required ReadSourcePolicy readSourcePolicy,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage,
        _connectorRuntime = connectorRuntime,
        _canonicalCacheStore = canonicalCacheStore,
        _syncQueueService = syncQueueService,
        _syncOrchestrator = syncOrchestrator,
        _readSourcePolicy = readSourcePolicy;

  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;
  final ConnectorRuntime _connectorRuntime;
  final CanonicalCacheStore _canonicalCacheStore;
  final SyncQueueService _syncQueueService;
  final SyncOrchestrator _syncOrchestrator;
  final ReadSourcePolicy _readSourcePolicy;
  final RefreshRunGate<_RefreshCycleResult> _refreshRunGate =
      RefreshRunGate<_RefreshCycleResult>();
  final RefreshRunGate<AuthenticatedStudentRefreshResult>
      _authenticatedRefreshRunGate =
      RefreshRunGate<AuthenticatedStudentRefreshResult>();
  final TypedV2RuntimeGate _typedV2RuntimeGate = const TypedV2RuntimeGate();
  TypedV2GateRuntimeState _typedV2GateState = TypedV2GateRuntimeState.empty();
  TypedV2CohortDecision? _typedV2CohortDecision;
  String _typedV2GateStateStudentId = '';

  @override
  Future<Map<String, String>> loadSavedCredentials() async {
    return _secureStorage.loadDiaryCredentials();
  }

  Future<AuthenticatedStudentRefreshResult> refreshAuthenticatedStudent(
    AuthSession session,
  ) {
    return _authenticatedRefreshRunGate.run(
      () => _refreshAuthenticatedStudentInternal(session),
      onCoalesced: () {
        _logPostLoginStage(
          stage: 'student_refresh_transaction_coalesced',
          outcome: 'join_inflight',
          details: {
            'student_id_hash': _stableStudentHash(session.studentId),
          },
        );
      },
    );
  }

  Future<AuthenticatedStudentRefreshResult>
      _refreshAuthenticatedStudentInternal(AuthSession session) async {
    final saved = await _secureStorage.loadDiaryCredentials();
    final source = (saved['source'] ?? '').trim();
    final login = (saved['login'] ?? '').trim();
    final password = (saved['password'] ?? '').trim();
    if (source != 'kundelik' || login.isEmpty || password.isEmpty) {
      throw const AppException(
        'provider_credentials_unavailable',
        'Saved Kundelik credentials are unavailable.',
      );
    }

    var activeSession = session;
    if (activeSession.expiresAt
        .isBefore(DateTime.now().toUtc().add(const Duration(minutes: 2)))) {
      final refreshed = await _tryRefreshSession(activeSession.refreshToken);
      if (refreshed == null || refreshed.studentId != activeSession.studentId) {
        throw const AppException(
          'session_expired',
          'The authenticated session could not be refreshed.',
        );
      }
      activeSession = refreshed;
    }

    final traceId = _buildTraceId(activeSession.studentId);
    _logPostLoginStage(
      stage: 'student_refresh_transaction_start',
      outcome: 'started',
      details: {
        'trace_id': traceId,
        'provider': source,
        'student_id_hash': _stableStudentHash(activeSession.studentId),
      },
    );
    try {
      await _ingestKundelikBundle(
        session: activeSession,
        credentials: DiaryAuthCredentials(
          source: source,
          login: login,
          password: password,
        ),
        seedLocalCache: false,
        queueOnUploadFailure: false,
        forceV2Ingest: true,
        traceId: traceId,
      );
      final typedResult = await _refreshCanonicalCacheV2(
        accessToken: activeSession.accessToken,
        studentId: activeSession.studentId,
        traceId: traceId,
      );
      if (typedResult.status != _RefreshCycleStatus.success) {
        throw const AppException(
          'typed_read_refresh_failed',
          'Typed-v2 refresh did not publish a complete snapshot.',
        );
      }
      final context = await _canonicalCacheStore.getActiveReadContext();
      if (context == null ||
          context.studentId != activeSession.studentId ||
          !context.hasCompleteV2Scope) {
        throw const AppException(
          'student_refresh_snapshot_unavailable',
          'A complete typed-v2 snapshot was not published.',
        );
      }
      _logPostLoginStage(
        stage: 'student_refresh_transaction_result',
        outcome: 'success',
        details: {
          'trace_id': traceId,
          'provider': context.provider,
          'read_mode': context.readMode,
          'window_key': context.windowKey,
          'snapshot_at': context.snapshotAt,
        },
      );
      return AuthenticatedStudentRefreshResult(
        session: activeSession,
        traceId: traceId,
        provider: context.provider,
        readMode: context.readMode,
        windowKey: context.windowKey,
        snapshotAt: context.snapshotAt,
      );
    } catch (error) {
      _logPostLoginStage(
        stage: 'student_refresh_transaction_result',
        outcome: 'failed_preserve_active_snapshot',
        details: {
          'trace_id': traceId,
          'provider': source,
          'error': _sanitizeError(error.toString()),
        },
      );
      rethrow;
    }
  }

  Future<AuthSession?> ensureSessionBaseline(AuthSession session) async {
    final saved = await _secureStorage.loadDiaryCredentials();
    final source = (saved['source'] ?? '').trim();
    await _hydrateTypedV2GateState(
      studentId: session.studentId,
      provider: source,
    );
    _typedV2CohortDecision =
        _readSourcePolicy.typedV2Decision(studentId: session.studentId);
    return _tryRestoreSessionBaseline(
      session: session,
      source: source,
    );
  }

  @override
  Future<AuthSession?> tryAutoLogin() async {
    final saved = await _secureStorage.loadDiaryCredentials();
    final source = (saved['source'] ?? '').trim();
    final login = (saved['login'] ?? '').trim();
    final password = (saved['password'] ?? '').trim();

    final storedSession = await _loadStoredSession();
    if (storedSession != null) {
      await _hydrateTypedV2GateState(
        studentId: storedSession.studentId,
        provider: source,
      );
      _typedV2CohortDecision =
          _readSourcePolicy.typedV2Decision(studentId: storedSession.studentId);
      AuthSession? candidateSession = storedSession;
      if (storedSession.expiresAt
          .isBefore(DateTime.now().toUtc().add(const Duration(minutes: 2)))) {
        candidateSession = await _tryRefreshSession(storedSession.refreshToken);
      }
      if (candidateSession != null) {
        await _hydrateTypedV2GateState(
          studentId: candidateSession.studentId,
          provider: source,
        );
        _typedV2CohortDecision = _readSourcePolicy.typedV2Decision(
          studentId: candidateSession.studentId,
        );
        final restored = await _tryRestoreSessionBaseline(
          session: candidateSession,
          source: source,
        );
        if (restored != null) {
          return restored;
        }
      }
    }

    if (source.isEmpty || login.isEmpty || password.isEmpty) {
      return null;
    }
    try {
      final session = await this.login(
        credentials: DiaryAuthCredentials(
          source: source,
          login: login,
          password: password,
        ),
      );
      final usable = await _hasUsableBaseline(
        studentId: session.studentId,
        expectedMode: _resolvedReadMode(studentId: session.studentId),
      );
      if (!usable) {
        _logPostLoginStage(
          stage: 'auth_restore_result',
          outcome: 'session_kept_post_login_baseline_incomplete',
          details: {
            'student_id_hash': _stableStudentHash(session.studentId),
          },
        );
        return session;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<AuthSession?> _tryRestoreSessionBaseline({
    required AuthSession session,
    required String source,
  }) async {
    try {
      await _refreshCanonicalCache(
        accessToken: session.accessToken,
        studentId: session.studentId,
      );
      await _runPendingSyncBestEffort(accessToken: session.accessToken);
      final usable = await _hasUsableBaseline(
        studentId: session.studentId,
        expectedMode: _resolvedReadMode(studentId: session.studentId),
      );
      if (usable) {
        return session;
      }
      throw const AppException(
        'bootstrap_incomplete',
        'Restored session has incomplete baseline data.',
      );
    } catch (_) {
      final refreshed = await _tryRefreshSession(session.refreshToken);
      if (refreshed != null) {
        await _hydrateTypedV2GateState(
          studentId: refreshed.studentId,
          provider: source,
        );
        _typedV2CohortDecision =
            _readSourcePolicy.typedV2Decision(studentId: refreshed.studentId);
        try {
          await _refreshCanonicalCache(
            accessToken: refreshed.accessToken,
            studentId: refreshed.studentId,
          );
          await _runPendingSyncBestEffort(accessToken: refreshed.accessToken);
          final usable = await _hasUsableBaseline(
            studentId: refreshed.studentId,
            expectedMode: _resolvedReadMode(studentId: refreshed.studentId),
          );
          if (usable) {
            return refreshed;
          }
        } catch (_) {
          // fall through to cached-baseline check
        }
      }

      final usableFromCache = await _hasUsableBaseline(
        studentId: session.studentId,
        expectedMode: _resolvedReadMode(studentId: session.studentId),
      );
      if (usableFromCache) {
        return session;
      }

      _logPostLoginStage(
        stage: 'auth_restore_result',
        outcome: 'session_kept_baseline_incomplete',
        details: {
          'student_id_hash': _stableStudentHash(session.studentId),
        },
      );
      return session;
    }
  }

  Future<bool> _hasUsableBaseline({
    required String studentId,
    required ReadSourceMode expectedMode,
  }) async {
    final context = await _canonicalCacheStore.getActiveReadContext();
    if (context == null) {
      return false;
    }
    if (context.studentId.trim().toLowerCase() !=
        studentId.trim().toLowerCase()) {
      return false;
    }

    if (expectedMode == ReadSourceMode.v2) {
      if (!context.hasCompleteV2Scope) {
        return false;
      }
      final identity = await _canonicalCacheStore.getV2ProviderIdentity(
        context: context,
      );
      if (identity == null) {
        return false;
      }
      final hasProviderIdentity =
          _string(identity['student_full_name']).isNotEmpty ||
              _string(identity['school_name']).isNotEmpty ||
              _string(identity['class_label']).isNotEmpty;
      if (!hasProviderIdentity) {
        return false;
      }
      final lessons =
          await _canonicalCacheStore.listV2Lessons(context: context);
      final results =
          await _canonicalCacheStore.listV2Results(context: context);
      return lessons.isNotEmpty || results.isNotEmpty;
    }

    final profile = await _canonicalCacheStore.getProfile();
    if (profile == null) {
      return false;
    }
    final hasProviderIdentity = _string(profile['first_name']).isNotEmpty ||
        _string(profile['last_name']).isNotEmpty ||
        _string(profile['school_name']).isNotEmpty ||
        _string(profile['class_label']).isNotEmpty;
    if (!hasProviderIdentity) {
      return false;
    }
    return true;
  }

  @override
  Future<AuthSession> login({required DiaryAuthCredentials credentials}) async {
    final loginResponse = await _apiClient.post(
      '/v1/auth/login',
      data: {
        'source': credentials.source,
        'login': credentials.login,
        'password': credentials.password,
      },
    );

    if (loginResponse.statusCode != 200 || loginResponse.data is! Map) {
      throw const AppException('login_failed', 'Unable to login.');
    }

    final session = _sessionFromResponse(loginResponse.data as Map);

    if (session.studentId.isEmpty || session.accessToken.isEmpty) {
      throw const AppException(
          'login_failed', 'Backend login response is incomplete.');
    }
    await _hydrateTypedV2GateState(
      studentId: session.studentId,
      provider: credentials.source,
    );
    _typedV2CohortDecision =
        _readSourcePolicy.typedV2Decision(studentId: session.studentId);
    _logPostLoginStage(
      stage: 'typed_read_cohort_decision',
      outcome: _typedV2CohortDecision!.mode.name,
      details: {
        'student_id_hash':
            _stableStudentHash(_typedV2CohortDecision!.studentId),
        'cohort_reason': _typedV2CohortDecision!.reason,
        if (_typedV2CohortDecision!.bucket != null)
          'cohort_bucket': _typedV2CohortDecision!.bucket,
        if (_typedV2CohortDecision!.percent != null)
          'cohort_percent': _typedV2CohortDecision!.percent,
      },
    );

    _logPostLoginStage(
      stage: 'persist_auth_start',
      outcome: 'started',
      details: {
        'source': credentials.source,
        'login': _redactLogin(credentials.login),
      },
    );
    await _secureStorage.saveDiaryCredentials(
      source: credentials.source,
      login: credentials.login,
      password: credentials.password,
    );
    await _secureStorage.saveAuthSession(
      studentId: session.studentId,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresAtIso: session.expiresAt.toUtc().toIso8601String(),
    );
    _logAuthSessionPersisted(session);
    _logPostLoginStage(
      stage: 'persist_auth_result',
      outcome: 'success',
      details: {
        'source': credentials.source,
        'login': _redactLogin(credentials.login),
      },
    );

    if (credentials.source == 'kundelik') {
      _logPostLoginStage(
        stage: 'initial_bootstrap_start',
        outcome: 'started',
        details: {
          'source': credentials.source,
          'login': _redactLogin(credentials.login),
        },
      );
      await _ingestKundelikBundle(session: session, credentials: credentials);
    }
    await _refreshCanonicalCache(
      accessToken: session.accessToken,
      studentId: session.studentId,
    );
    await _runPendingSyncBestEffort(accessToken: session.accessToken);

    return session;
  }

  Future<void> _runPendingSyncBestEffort({
    required String accessToken,
  }) async {
    try {
      await _syncOrchestrator.runPending(accessToken: accessToken);
    } catch (error) {
      _logPostLoginStage(
        stage: 'sync_failed',
        outcome: 'run_pending_failed_non_blocking',
        details: {
          'error': _sanitizeError(error.toString()),
        },
      );
    }
  }

  Future<AuthSession?> _loadStoredSession() async {
    final stored = await _secureStorage.loadAuthSession();
    final studentId = (stored['student_id'] ?? '').trim();
    final accessToken = (stored['access_token'] ?? '').trim();
    final refreshToken = (stored['refresh_token'] ?? '').trim();
    final expiresAtRaw = (stored['expires_at'] ?? '').trim();
    if (studentId.isEmpty || accessToken.isEmpty || expiresAtRaw.isEmpty) {
      return null;
    }
    final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
    if (expiresAt == null) {
      return null;
    }
    return AuthSession(
      studentId: studentId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    );
  }

  Future<AuthSession?> _tryRefreshSession(String refreshToken) async {
    final normalized = refreshToken.trim();
    if (normalized.isEmpty) {
      return null;
    }
    try {
      final response = await _apiClient.post(
        '/v1/auth/refresh',
        data: {'refresh_token': normalized},
      );
      if (response.statusCode != 200 || response.data is! Map) {
        return null;
      }
      final session = _sessionFromResponse(response.data as Map);
      if (session.studentId.isEmpty || session.accessToken.isEmpty) {
        return null;
      }
      await _secureStorage.saveAuthSession(
        studentId: session.studentId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAtIso: session.expiresAt.toUtc().toIso8601String(),
      );
      _logAuthSessionPersisted(session);
      return session;
    } catch (_) {
      return null;
    }
  }

  AuthSession _sessionFromResponse(Map raw) {
    final data = Map<String, dynamic>.from(
      raw['data'] as Map? ?? raw,
    );
    return AuthSession(
      studentId: data['student_id']?.toString() ?? '',
      accessToken: data['access_token']?.toString() ?? '',
      refreshToken: data['refresh_token']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(data['expires_at']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc().add(const Duration(minutes: 20)),
    );
  }

  Future<void> _ingestKundelikBundle({
    required AuthSession session,
    required DiaryAuthCredentials credentials,
    bool seedLocalCache = true,
    bool queueOnUploadFailure = true,
    bool forceV2Ingest = false,
    String traceId = '',
  }) async {
    final connector = _connectorRuntime.create('kundelik');
    await connector.authenticate(credentials);

    final academicYearWindow =
        AcademicYearWindow.forNowUtc(DateTime.now().toUtc());
    final bundle = await connector.buildCanonicalBundle(
      DiarySyncRequest(
        idempotencyKey:
            'mobile-${DateTime.now().toUtc().millisecondsSinceEpoch}',
        from: academicYearWindow.startUtc,
        to: academicYearWindow.endUtc,
      ),
    );
    _logPostLoginStage(
      stage: 'initial_bootstrap_result',
      outcome: 'success',
      details: {
        'source': credentials.source,
        'login': _redactLogin(credentials.login),
        if (traceId.isNotEmpty) 'trace_id': traceId,
        'has_person_id': (bundle.sourceIds['person_id'] ?? '').isNotEmpty,
        'has_school_id': (bundle.sourceIds['school_id'] ?? '').isNotEmpty,
        'has_group_id': (bundle.sourceIds['group_id'] ?? '').isNotEmpty,
      },
    );
    if (seedLocalCache) {
      await _seedCanonicalCacheFromBundle(
        studentId: session.studentId,
        bundle: bundle,
      );
    }

    try {
      final useV2Ingest = forceV2Ingest ||
          _resolvedReadMode(studentId: session.studentId) == ReadSourceMode.v2;
      final payload = useV2Ingest ? bundle.toV2Json() : bundle.toV1Json();
      final ingestEndpoint =
          useV2Ingest ? '/v2/ingest/bundle' : '/v1/ingest/bundle';
      final payloadKeys = payload.keys.toList(growable: false);
      final lessons = bundle.lessons;
      final homeworkCount =
          lessons.where((item) => item.homeworkText.trim().isNotEmpty).length;
      final gradesCount = useV2Ingest
          ? bundle.results.length
          : lessons.fold<int>(
              0,
              (sum, lesson) => sum + lesson.grades.length,
            );
      final aggregatesCount = useV2Ingest ? bundle.aggregates.length : 0;
      final lessonPayloadSample = _extractLessonPayloadSample(payload);
      final canonicalLessonDateSample =
          lessons.isNotEmpty ? lessons.first.date : '';
      final lessonDateFormat =
          _detectDateFormat(lessonPayloadSample['date_sample'] ?? '');
      final timeFormat =
          _detectTimeFormat(lessonPayloadSample['start_time_sample'] ?? '');
      _logPostLoginStage(
        stage: 'ingest_start',
        outcome: 'started',
        details: {
          'endpoint': ingestEndpoint,
          'window_from': academicYearWindow.windowFrom,
          'window_to': academicYearWindow.windowTo,
          'source': credentials.source,
          'login': _redactLogin(credentials.login),
          if (traceId.isNotEmpty) 'trace_id': traceId,
          'bundle_version': useV2Ingest ? 2 : 1,
          'payload_keys': payloadKeys,
          'payload_lessons_count': lessons.length,
          'payload_homework_count': homeworkCount,
          'payload_grades_count': gradesCount,
          'payload_aggregates_count': aggregatesCount,
          'payload_lesson_date_format': lessonDateFormat,
          'payload_lesson_time_format': timeFormat,
          'payload_lesson_date_sample': lessonPayloadSample['date_sample'],
          'payload_lesson_start_time_sample':
              lessonPayloadSample['start_time_sample'],
          'payload_lesson_end_time_sample':
              lessonPayloadSample['end_time_sample'],
          'canonical_lesson_date_sample': canonicalLessonDateSample,
          'has_person_id': (bundle.sourceIds['person_id'] ?? '').isNotEmpty,
          'has_school_id': (bundle.sourceIds['school_id'] ?? '').isNotEmpty,
          'has_group_id': (bundle.sourceIds['group_id'] ?? '').isNotEmpty,
        },
      );
      final response = await _apiClient.post(
        ingestEndpoint,
        options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'}),
        data: payload,
      );
      await _syncQueueService.markSynced(bundle.idempotencyKey);
      _logPostLoginStage(
        stage: 'ingest_result',
        outcome: 'success',
        details: {
          'source': credentials.source,
          'status': response.statusCode,
          if (traceId.isNotEmpty) 'trace_id': traceId,
        },
      );
    } on DioException catch (error) {
      final useV2Ingest = forceV2Ingest ||
          _resolvedReadMode(studentId: session.studentId) == ReadSourceMode.v2;
      final ingestEndpoint =
          useV2Ingest ? '/v2/ingest/bundle' : '/v1/ingest/bundle';
      if (queueOnUploadFailure) {
        await _syncQueueService.enqueue(bundle, useV2Ingest: useV2Ingest);
        await _syncQueueService.markFailure(
          bundle.idempotencyKey,
          SyncFailure(
            type: SyncFailureType.transient,
            message: error.message ?? 'ingest request failed',
          ),
          1,
        );
      }
      _logPostLoginStage(
        stage: 'ingest_result',
        outcome:
            queueOnUploadFailure ? 'queued_after_failure' : 'failed_not_queued',
        details: {
          'endpoint': ingestEndpoint,
          'bundle_version': useV2Ingest ? 2 : 1,
          'source': credentials.source,
          if (traceId.isNotEmpty) 'trace_id': traceId,
          'status': error.response?.statusCode,
          'response_sanitized': _sanitizeIngestResponse(error.response?.data),
        },
      );
      _logPostLoginStage(
        stage: 'sync_failed',
        outcome: queueOnUploadFailure
            ? 'ingest_failed_queued'
            : 'ingest_failed_not_queued',
        details: {
          'endpoint': ingestEndpoint,
          'status': error.response?.statusCode,
          'error': _sanitizeError(error.message ?? 'ingest request failed'),
        },
      );
      if (!queueOnUploadFailure) {
        rethrow;
      }
    }
  }

  Future<void> _refreshCanonicalCache({
    required String accessToken,
    required String studentId,
    String? traceId,
    bool requirePublishedSuccess = false,
  }) async {
    final resolvedTraceId = traceId ?? _buildTraceId(studentId);
    final result = await _refreshRunGate.run(
      () => _refreshCanonicalCacheInternal(
        accessToken: accessToken,
        studentId: studentId,
        traceId: resolvedTraceId,
      ),
      onCoalesced: () {
        _logPostLoginStage(
          stage: 'typed_read_refresh_coalesced',
          outcome: 'join_inflight',
          details: {
            'read_mode': _resolvedReadMode(studentId: studentId).name,
            'trace_id': resolvedTraceId,
          },
        );
      },
    );
    if (result.status == _RefreshCycleStatus.failed ||
        (requirePublishedSuccess &&
            result.status != _RefreshCycleStatus.success)) {
      _logPostLoginStage(
        stage: 'sync_failed',
        outcome: 'typed_read_refresh_failed',
        details: {
          'trace_id': result.traceId,
          'read_mode': result.mode,
          if (result.fallbackReason.isNotEmpty)
            'fallback_reason': result.fallbackReason,
          if (result.errorCode.isNotEmpty) 'error_code': result.errorCode,
        },
      );
      throw AppException(
        result.errorCode.isEmpty
            ? 'typed_read_refresh_failed'
            : result.errorCode,
        result.errorMessage.isEmpty
            ? 'Typed read refresh failed'
            : result.errorMessage,
      );
    }
  }

  Future<_RefreshCycleResult> _refreshCanonicalCacheInternal({
    required String accessToken,
    required String studentId,
    required String traceId,
  }) async {
    final academicYearWindow =
        AcademicYearWindow.forNowUtc(DateTime.now().toUtc());
    _logPostLoginStage(
      stage: 'typed_read_refresh_start',
      outcome: 'started',
      details: {
        'read_mode': _resolvedReadMode(studentId: studentId).name,
        'trace_id': traceId,
        'window_from': academicYearWindow.windowFrom,
        'window_to': academicYearWindow.windowTo,
      },
    );

    if (_resolvedReadMode(studentId: studentId) == ReadSourceMode.v2) {
      try {
        return await _refreshCanonicalCacheV2(
          accessToken: accessToken,
          studentId: studentId,
          traceId: traceId,
        );
      } catch (error) {
        final fallbackReason = _readSourcePolicy.fallbackReasonCode(error);
        if (_readSourcePolicy.isTransportFailureEligibleForFallback(error)) {
          _logPostLoginStage(
            stage: 'typed_read_v2_transport_fallback',
            outcome: 'fallback_to_v1',
            details: {
              'fallback_reason': fallbackReason,
              'trace_id': traceId,
              'error': _sanitizeError(error.toString()),
            },
          );
          _logPostLoginStage(
            stage: 'typed_read_v2_degraded_refresh',
            outcome: 'degraded',
            details: {
              'fallback_reason': fallbackReason,
              'trace_id': traceId,
            },
          );
          try {
            return await _refreshCanonicalCacheV1(
              accessToken: accessToken,
              studentId: studentId,
              traceId: traceId,
              isDegradedFallback: true,
              fallbackReason: fallbackReason,
            );
          } catch (fallbackError) {
            await _canonicalCacheStore.recordRefreshFailure(
              studentId: studentId,
              provider: 'kundelik',
              attemptedReadMode: 'v1',
              fallbackReason: fallbackReason,
              errorCode: 'typed_read_refresh_failed',
              traceId: traceId,
            );
            _logPostLoginStage(
              stage: 'typed_read_refresh_result',
              outcome: 'failed',
              details: {
                'read_mode': 'v1',
                'refresh_status': 'failed',
                'fallback_reason': fallbackReason,
                'trace_id': traceId,
                'error': _sanitizeError(fallbackError.toString()),
              },
            );
            return _RefreshCycleResult(
              status: _RefreshCycleStatus.failed,
              mode: 'v1',
              provider: 'kundelik',
              fallbackReason: fallbackReason,
              traceId: traceId,
              errorCode: 'typed_read_refresh_failed',
              errorMessage: 'v1 fallback refresh failed',
            );
          }
        }
        _logPostLoginStage(
          stage: 'typed_read_v2_failed',
          outcome: 'no_fallback',
          details: {
            'fallback_reason': fallbackReason,
            'trace_id': traceId,
            'error': _sanitizeError(error.toString()),
          },
        );
        await _canonicalCacheStore.recordRefreshFailure(
          studentId: studentId,
          provider: 'kundelik',
          attemptedReadMode: 'v2',
          fallbackReason: fallbackReason,
          errorCode: 'typed_read_v2_failed',
          traceId: traceId,
        );
        _logPostLoginStage(
          stage: 'typed_read_refresh_result',
          outcome: 'failed',
          details: {
            'read_mode': 'v2',
            'refresh_status': 'failed',
            'fallback_reason': fallbackReason,
            'trace_id': traceId,
          },
        );
        return _RefreshCycleResult(
          status: _RefreshCycleStatus.failed,
          mode: 'v2',
          provider: 'kundelik',
          fallbackReason: fallbackReason,
          traceId: traceId,
          errorCode: 'typed_read_v2_failed',
          errorMessage: 'v2 refresh failed without fallback',
        );
      }
    }

    return _refreshCanonicalCacheV1(
      accessToken: accessToken,
      studentId: studentId,
      traceId: traceId,
      isDegradedFallback: false,
    );
  }

  Future<_RefreshCycleResult> _refreshCanonicalCacheV2({
    required String accessToken,
    required String studentId,
    required String traceId,
  }) async {
    final refreshSnapshotAt = DateTime.now().toUtc().toIso8601String();
    final headers = Options(headers: {
      'Authorization': 'Bearer $accessToken',
      'X-Trace-Id': traceId,
    });
    final academicYearWindow =
        AcademicYearWindow.forNowUtc(DateTime.now().toUtc());
    final from = academicYearWindow.windowFrom;
    final to = academicYearWindow.windowTo;
    final query = <String, dynamic>{
      'provider': 'kundelik',
      'window_from': from,
      'window_to': to,
      'limit': 300,
      'snapshot_at': refreshSnapshotAt,
    };

    _logPostLoginStage(
      stage: 'typed_read_v2_request_profile',
      outcome: 'start',
      details: {
        'trace_id': traceId,
        'path': '/v2/profile',
        'snapshot_at': refreshSnapshotAt,
      },
    );
    final profileWatch = Stopwatch()..start();
    final profileResponse = await _apiClient.get(
      '/v2/profile',
      options: headers,
      queryParameters: query,
    );
    profileWatch.stop();
    _logPostLoginStage(
      stage: 'typed_read_v2_request_profile',
      outcome: 'result',
      details: {
        'trace_id': traceId,
        'path': '/v2/profile',
        'snapshot_at': refreshSnapshotAt,
        'status': profileResponse.statusCode,
      },
    );

    _logPostLoginStage(
      stage: 'typed_read_v2_request_results',
      outcome: 'start',
      details: {
        'trace_id': traceId,
        'path': '/v2/results',
        'snapshot_at': refreshSnapshotAt,
      },
    );
    final resultsWatch = Stopwatch()..start();
    final resultsResponse = await _apiClient.get(
      '/v2/results',
      options: headers,
      queryParameters: query,
    );
    resultsWatch.stop();
    _logPostLoginStage(
      stage: 'typed_read_v2_request_results',
      outcome: 'result',
      details: {
        'trace_id': traceId,
        'path': '/v2/results',
        'snapshot_at': refreshSnapshotAt,
        'status': resultsResponse.statusCode,
      },
    );

    _logPostLoginStage(
      stage: 'typed_read_v2_request_overview',
      outcome: 'start',
      details: {
        'trace_id': traceId,
        'path': '/v2/academic/overview',
        'snapshot_at': refreshSnapshotAt,
      },
    );
    final overviewWatch = Stopwatch()..start();
    final overviewResponse = await _apiClient.get(
      '/v2/academic/overview',
      options: headers,
      queryParameters: query,
    );
    overviewWatch.stop();
    _logPostLoginStage(
      stage: 'typed_read_v2_request_overview',
      outcome: 'result',
      details: {
        'trace_id': traceId,
        'path': '/v2/academic/overview',
        'snapshot_at': refreshSnapshotAt,
        'status': overviewResponse.statusCode,
      },
    );

    final profileData = _extractDataMap(profileResponse);
    final resultsData = _extractDataMap(resultsResponse);
    final overviewData = _extractDataMap(overviewResponse);
    if (profileData == null || resultsData == null || overviewData == null) {
      throw const FormatException('v2 dto schema mismatch');
    }

    final profileDto = V2ProfileResponse.fromJson(profileData);
    final resultsDto = V2ResultsResponse.fromJson(resultsData);
    final overviewDto = V2OverviewResponse.fromJson(overviewData);
    final profileSnapshot = profileDto.window.snapshotAt;
    final resultsSnapshot = resultsDto.window.snapshotAt;
    final overviewSnapshot = overviewDto.window.snapshotAt;
    final sameSnapshot = profileSnapshot == resultsSnapshot &&
        profileSnapshot == overviewSnapshot;
    if (!sameSnapshot) {
      _logPostLoginStage(
        stage: 'typed_read_v2_snapshot_inconsistency',
        outcome: 'failed',
        details: {
          'trace_id': traceId,
          'profile_snapshot_at': profileSnapshot,
          'results_snapshot_at': resultsSnapshot,
          'overview_snapshot_at': overviewSnapshot,
        },
      );
      throw const AppException(
        'typed_read_v2_snapshot_inconsistent',
        'v2 refresh returned inconsistent snapshot_at values',
      );
    }

    final provider = profileDto.window.provider;
    final totalStats = await _canonicalCacheStore.applyV2RefreshSnapshot(
      studentId: studentId,
      profile: profileDto,
      results: resultsDto,
      overview: overviewDto,
      traceId: traceId,
    );
    _logPostLoginStage(
      stage: 'typed_read_refresh_result',
      outcome: 'success',
      details: {
        'read_mode': 'v2',
        'refresh_status': 'success',
        'provider': profileDto.window.provider,
        'window_key': profileDto.window.windowKey,
        'snapshot_at': profileDto.window.snapshotAt,
        'lessons_count': resultsDto.lessons.length,
        'results_count': resultsDto.results.length,
        'aggregates_count': resultsDto.aggregates.length,
        'attendance_count': resultsDto.attendance.length,
        'latency_profile_ms': profileWatch.elapsedMilliseconds,
        'latency_results_ms': resultsWatch.elapsedMilliseconds,
        'latency_overview_ms': overviewWatch.elapsedMilliseconds,
        'rows_deleted': totalStats.rowsDeleted,
        'rows_written': totalStats.rowsWritten,
        'trace_id': traceId,
      },
    );
    if (_readSourcePolicy.enableV2ParityShadow) {
      await _runV1ParityShadow(
        accessToken: accessToken,
        profileData: profileData,
        resultsData: resultsData,
        windowKey: profileDto.window.windowKey,
        snapshotAt: profileDto.window.snapshotAt,
        traceId: traceId,
      );
    }
    return _RefreshCycleResult(
      status: _RefreshCycleStatus.success,
      mode: 'v2',
      provider: provider,
      traceId: traceId,
    );
  }

  Future<_RefreshCycleResult> _refreshCanonicalCacheV1({
    required String accessToken,
    required String studentId,
    required String traceId,
    required bool isDegradedFallback,
    String fallbackReason = '',
  }) async {
    final headers = Options(headers: {
      'Authorization': 'Bearer $accessToken',
      'X-Trace-Id': traceId,
    });

    final profileResponse =
        await _apiClient.get('/v1/profile', options: headers);
    final lessonsResponse =
        await _apiClient.get('/v1/lessons', options: headers);
    final homeworkResponse =
        await _apiClient.get('/v1/homework', options: headers);
    final gradesResponse = await _apiClient.get('/v1/grades', options: headers);

    final profileData = _extractDataMap(profileResponse);
    final lessonsData = _extractDataList(lessonsResponse);
    final homeworkData = _extractDataList(homeworkResponse);
    final gradesData = _extractDataList(gradesResponse);
    if (profileData == null ||
        lessonsData == null ||
        homeworkData == null ||
        gradesData == null) {
      throw const FormatException('v1 dto schema mismatch');
    }

    final normalizedProfile = _normalizeV1ProfilePayload(
      profileData: profileData,
      studentId: studentId,
    );
    if (_hasProviderIdentityPayload(normalizedProfile)) {
      await _canonicalCacheStore.upsertProfile(normalizedProfile);
    } else {
      _logPostLoginStage(
        stage: 'typed_read_v1_profile_apply',
        outcome: 'skipped_empty_payload_preserve_cache',
        details: {'trace_id': traceId},
      );
    }
    await _canonicalCacheStore.replaceLessons(lessonsData);
    await _canonicalCacheStore.replaceHomework(homeworkData);
    if (gradesData.isNotEmpty) {
      await _canonicalCacheStore.replaceGrades(gradesData);
    } else {
      _logPostLoginStage(
        stage: 'typed_read_v1_grades_apply',
        outcome: 'skipped_empty_payload_preserve_cache',
        details: {'trace_id': traceId},
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final refreshStatus = isDegradedFallback ? 'degraded' : 'success';
    await _canonicalCacheStore.setReadMode(
      studentId: studentId,
      provider: 'kundelik',
      mode: 'v1',
      windowKey: 'kundelik:v1',
      snapshotAt: now,
      refreshMode: isDegradedFallback ? 'degraded_v1_fallback' : 'v1',
      refreshStatus: refreshStatus,
      fallbackReason: fallbackReason,
      traceId: traceId,
      publishActiveState: !isDegradedFallback,
    );
    _logPostLoginStage(
      stage: 'typed_read_refresh_result',
      outcome: isDegradedFallback ? 'degraded' : 'success',
      details: {
        'read_mode': 'v1',
        'refresh_status': refreshStatus,
        'last_refresh_mode': isDegradedFallback ? 'degraded_v1_fallback' : 'v1',
        'provider': 'kundelik',
        'window_key': 'kundelik:v1',
        'snapshot_at': now,
        if (fallbackReason.isNotEmpty) 'fallback_reason': fallbackReason,
        'trace_id': traceId,
      },
    );
    return _RefreshCycleResult(
      status: isDegradedFallback
          ? _RefreshCycleStatus.degraded
          : _RefreshCycleStatus.success,
      mode: 'v1',
      provider: 'kundelik',
      traceId: traceId,
      fallbackReason: fallbackReason,
    );
  }

  Future<void> _seedCanonicalCacheFromBundle({
    required String studentId,
    required CanonicalBundle bundle,
  }) async {
    final profilePayload = <String, dynamic>{
      'student_id': studentId,
      'first_name': bundle.profile.firstName,
      'last_name': bundle.profile.lastName,
      'grade_level': bundle.profile.gradeLevel,
      'class_label': bundle.profile.classLabel,
      'school_name': bundle.profile.schoolName,
    };
    await _canonicalCacheStore.upsertProfile(profilePayload);

    final lessonsPayload = bundle.lessons
        .map(
          (lesson) => <String, dynamic>{
            'lesson_id': lesson.sourceLessonKey,
            'date': lesson.date,
            'lesson_number': lesson.lessonNumber,
            'subject_name': lesson.subjectName,
            'topic': lesson.topicTitle,
            'homework_text': lesson.homeworkText,
            'requires_photo': lesson.requiresPhoto,
            'grade_value':
                lesson.grades.isNotEmpty ? lesson.grades.first.value : '',
            'grade_mood':
                lesson.grades.isNotEmpty ? lesson.grades.first.mood : '',
            'attendance_code': '',
          },
        )
        .toList(growable: false);
    await _canonicalCacheStore.replaceLessons(lessonsPayload);

    final homeworkPayload = bundle.lessons
        .where((lesson) => lesson.homeworkText.trim().isNotEmpty)
        .map(
          (lesson) => <String, dynamic>{
            'homework_id': 'hw:${lesson.sourceLessonKey}',
            'description': lesson.homeworkText,
            'requires_photo': lesson.requiresPhoto,
            'lesson_date': lesson.date,
            'subject_name': lesson.subjectName,
          },
        )
        .toList(growable: false);
    await _canonicalCacheStore.replaceHomework(homeworkPayload);

    final gradeRows = <Map<String, dynamic>>[];
    for (final item in bundle.results.where((r) => r.resultKind == 'regular')) {
      if (item.valueText.trim().isEmpty) {
        continue;
      }
      gradeRows.add(<String, dynamic>{
        'value': item.valueText,
        'mood': item.resolvedMood,
        'grade_type': 'regular',
        'created_at': item.recordedOn,
      });
    }
    if (gradeRows.isEmpty) {
      for (final lesson in bundle.lessons) {
        for (final grade in lesson.grades) {
          if (grade.value.trim().isEmpty) {
            continue;
          }
          gradeRows.add(<String, dynamic>{
            'value': grade.value,
            'mood': grade.mood,
            'grade_type': grade.type,
            'created_at': lesson.date,
          });
        }
      }
    }
    if (gradeRows.isNotEmpty) {
      await _canonicalCacheStore.replaceGrades(gradeRows);
    }
  }

  Map<String, dynamic> _normalizeV1ProfilePayload({
    required Map<String, dynamic> profileData,
    required String studentId,
  }) {
    final providerIdentity =
        profileData['provider_identity'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(
                profileData['provider_identity'] as Map<String, dynamic>,
              )
            : (profileData['provider_identity'] is Map
                ? Map<String, dynamic>.from(
                    profileData['provider_identity'] as Map,
                  )
                : const <String, dynamic>{});

    final firstName = _string(profileData['first_name']);
    final lastName = _string(profileData['last_name']);
    final studentFullName = _string(providerIdentity['student_full_name']);
    final split = _splitFullName(studentFullName);
    final classLabel = _string(profileData['class_label']).isNotEmpty
        ? _string(profileData['class_label'])
        : _string(providerIdentity['class_label']);
    final schoolName = _string(profileData['school_name']).isNotEmpty
        ? _string(profileData['school_name'])
        : _string(providerIdentity['school_name']);

    return <String, dynamic>{
      'student_id': _string(profileData['student_id']).isNotEmpty
          ? _string(profileData['student_id'])
          : studentId,
      'first_name': firstName.isNotEmpty ? firstName : split.$1,
      'last_name': lastName.isNotEmpty ? lastName : split.$2,
      'grade_level': int.tryParse(_string(profileData['grade_level'])) ?? 1,
      'class_label': classLabel,
      'school_name': schoolName,
    };
  }

  (String, String) _splitFullName(String fullName) {
    final normalized = fullName.trim();
    if (normalized.isEmpty) {
      return ('', '');
    }
    final parts =
        normalized.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final list = parts.toList(growable: false);
    if (list.isEmpty) {
      return ('', '');
    }
    if (list.length == 1) {
      return (list.first, '');
    }
    return (list.first, list.sublist(1).join(' '));
  }

  bool _hasProviderIdentityPayload(Map<String, dynamic> payload) {
    return _string(payload['first_name']).isNotEmpty ||
        _string(payload['last_name']).isNotEmpty ||
        _string(payload['class_label']).isNotEmpty ||
        _string(payload['school_name']).isNotEmpty;
  }

  Future<void> _runV1ParityShadow({
    required String accessToken,
    required Map<String, dynamic> profileData,
    required Map<String, dynamic> resultsData,
    required String windowKey,
    required String snapshotAt,
    required String traceId,
  }) async {
    final headers = Options(headers: {
      'Authorization': 'Bearer $accessToken',
      'X-Trace-Id': traceId,
    });
    try {
      final v1ProfileResponse =
          await _apiClient.get('/v1/profile', options: headers);
      final v1GradesResponse =
          await _apiClient.get('/v1/grades', options: headers);
      final v1LessonsResponse =
          await _apiClient.get('/v1/lessons', options: headers);
      final v1AttendanceResponse =
          await _apiClient.get('/v1/attendance', options: headers);

      final v1Profile =
          _extractDataMap(v1ProfileResponse) ?? const <String, dynamic>{};
      final extractedV1Grades = _extractDataList(v1GradesResponse);
      final v1Grades = extractedV1Grades ?? const <dynamic>[];
      final v1Lessons =
          _extractDataList(v1LessonsResponse) ?? const <dynamic>[];
      final v1Attendance =
          _extractDataList(v1AttendanceResponse) ?? const <dynamic>[];
      final v1GradesShape = _describePayloadShape(v1GradesResponse.data);

      final v2Identity = (profileData['provider_identity'] is Map)
          ? Map<String, dynamic>.from(profileData['provider_identity'] as Map)
          : const <String, dynamic>{};
      final v2Window = (resultsData['window'] is Map)
          ? Map<String, dynamic>.from(resultsData['window'] as Map)
          : const <String, dynamic>{};
      final windowFrom = _string(v2Window['window_from']);
      final windowTo = _string(v2Window['window_to']);
      var parityResultsSource = 'refresh_payload';
      Map<String, dynamic> parityV2ResultsData = const <String, dynamic>{};
      try {
        final parityV2ResultsResponse = await _apiClient.get(
          '/v2/results',
          options: headers,
          queryParameters: <String, dynamic>{
            'provider': _string(v2Window['provider']).isEmpty
                ? 'kundelik'
                : _string(v2Window['provider']),
            'window_from': windowFrom,
            'window_to': windowTo,
            'snapshot_at': snapshotAt,
            'limit': 1000,
          },
        );
        final parsed = _extractDataMap(parityV2ResultsResponse);
        if (parsed != null && parsed.isNotEmpty) {
          parityV2ResultsData = parsed;
          parityResultsSource = 'v2_results_refetch';
        }
      } catch (_) {
        parityResultsSource = 'refresh_payload_refetch_failed';
      }
      final effectiveV2ResultsData =
          parityV2ResultsData.isEmpty ? resultsData : parityV2ResultsData;
      final v2Results = effectiveV2ResultsData['results'] as List<dynamic>? ??
          const <dynamic>[];
      final v2Lessons = effectiveV2ResultsData['lessons'] as List<dynamic>? ??
          const <dynamic>[];
      final v2Aggregates =
          effectiveV2ResultsData['aggregates'] as List<dynamic>? ??
              const <dynamic>[];
      final v2Attendance =
          effectiveV2ResultsData['attendance'] as List<dynamic>? ??
              const <dynamic>[];
      final parity = evaluateTypedReadParityShadow(
        v1Profile: v1Profile,
        v1Grades: v1Grades,
        v1Lessons: v1Lessons,
        v1Attendance: v1Attendance,
        v2Identity: v2Identity,
        v2Results: v2Results,
        v2Lessons: v2Lessons,
        v2Aggregates: v2Aggregates,
        v2Attendance: v2Attendance,
        windowFrom: windowFrom,
        windowTo: windowTo,
      );
      final v1GradesShapeHasItemsList =
          (v1GradesShape['data_list_keys'] is List) &&
              (v1GradesShape['data_list_keys'] as List)
                  .map((item) => item.toString())
                  .contains('items');
      final isV1GradesSourceEmptyCase = extractedV1Grades != null &&
          v1Grades.isEmpty &&
          v2Results.isNotEmpty &&
          v1GradesShapeHasItemsList;
      final isDowngradableV1GradesSourceEmptyMismatch =
          isV1GradesSourceEmptyCase &&
              !parity.profileMismatch &&
              parity.mismatchReason.isNotEmpty;
      final emittedMismatchReason = isDowngradableV1GradesSourceEmptyMismatch
          ? 'v1_grades_source_empty'
          : parity.mismatchReason;
      final parityStatus = isDowngradableV1GradesSourceEmptyMismatch
          ? 'watch'
          : (parity.mismatchReason.isEmpty ? 'ok' : 'mismatch');

      _logPostLoginStage(
        stage: 'typed_read_parity_shadow',
        outcome: parityStatus,
        details: {
          'read_mode': 'v2',
          'provider': _string(v2Identity['provider']),
          'window_key': windowKey,
          'snapshot_at': snapshotAt,
          'v1_grades_count': parity.v1ResultsCount,
          'v1_grades_rows_extracted': v1Grades.length,
          'v1_grades_extract_status': extractedV1Grades == null
              ? 'null'
              : (v1Grades.isEmpty ? 'empty' : 'ok'),
          'v1_grades_raw_shape': v1GradesShape,
          'v1_lessons_rows_extracted': v1Lessons.length,
          'v2_results_count': parity.v2ResultsCount,
          'v2_results_rows_effective': v2Results.length,
          'v1_lessons_count': parity.v1LessonsCount,
          'v2_lessons_count': parity.v2LessonsCount,
          'v1_attendance_count': parity.v1AttendanceCount,
          'v2_attendance_count': parity.v2AttendanceCount,
          'v1_aggregates_count': parity.v1AggregatesCount,
          'v2_aggregates_count': parity.v2AggregatesCount,
          'count_match': parity.countMatch,
          'identity_match': parity.identityMatch,
          'mood_match': parity.moodMatch,
          'aggregate_match': parity.aggregateMatch,
          'mood_mismatch': parity.moodMatch ? 0 : 1,
          'identity_mismatch': parity.identityMatch ? 0 : 1,
          'aggregate_mismatch': parity.aggregateMatch ? 0 : 1,
          'attendance_status_match': parity.attendanceStatusMatch,
          'profile_mismatch': parity.profileMismatch,
          'trace_id': traceId,
          'parity_v2_results_source': parityResultsSource,
          if (emittedMismatchReason.isNotEmpty)
            'typed_read_parity_shadow_mismatch_reason': emittedMismatchReason,
          if (isDowngradableV1GradesSourceEmptyMismatch)
            'parity_policy_note': 'downgraded_v1_grades_source_empty',
        },
      );
    } catch (error) {
      _logPostLoginStage(
        stage: 'typed_read_parity_shadow',
        outcome: 'failed',
        details: {
          'read_mode': 'v2',
          'window_key': windowKey,
          'snapshot_at': snapshotAt,
          'trace_id': traceId,
          'typed_read_parity_shadow_mismatch_reason': 'mixed',
          'error': _sanitizeError(error.toString()),
        },
      );
    }
  }

  Map<String, dynamic>? _extractDataMap(Response<dynamic> response) {
    if (response.data is! Map) {
      return null;
    }
    final root = Map<String, dynamic>.from(response.data as Map);
    final data = root['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return root;
  }

  List<dynamic>? _extractDataList(Response<dynamic> response) {
    if (response.data is List) {
      return List<dynamic>.from(response.data as List);
    }
    if (response.data is! Map) {
      return null;
    }
    final root = Map<String, dynamic>.from(response.data as Map);
    final data = root['data'];
    if (data is List) {
      return List<dynamic>.from(data);
    }
    if (data is Map) {
      final listFromData =
          _extractListFromEnvelope(Map<String, dynamic>.from(data));
      if (listFromData != null) {
        return listFromData;
      }
    }
    final listFromRoot = _extractListFromEnvelope(root);
    if (listFromRoot != null) {
      return listFromRoot;
    }
    return null;
  }

  List<dynamic>? _extractListFromEnvelope(Map<String, dynamic> envelope) {
    if (envelope['items'] is List) {
      return List<dynamic>.from(envelope['items'] as List);
    }
    for (final key in <String>[
      'grades',
      'lessons',
      'homework',
      'attendance',
      'results',
      'rows',
      'entries',
    ]) {
      if (envelope[key] is List) {
        return List<dynamic>.from(envelope[key] as List);
      }
    }
    List<dynamic>? onlyListValue;
    for (final value in envelope.values) {
      if (value is List) {
        if (onlyListValue != null) {
          return null;
        }
        onlyListValue = List<dynamic>.from(value);
      }
    }
    if (onlyListValue != null) {
      return onlyListValue;
    }
    final nested = <dynamic>[];
    _collectNestedLists(envelope, nested, 0, 3);
    if (nested.isEmpty) {
      return null;
    }
    return nested;
  }

  void _collectNestedLists(
    dynamic node,
    List<dynamic> out,
    int depth,
    int maxDepth,
  ) {
    if (depth > maxDepth) {
      return;
    }
    if (node is List) {
      for (final item in node) {
        out.add(item);
      }
      return;
    }
    if (node is Map) {
      for (final value in node.values) {
        _collectNestedLists(value, out, depth + 1, maxDepth);
      }
    }
  }

  Map<String, dynamic> _describePayloadShape(dynamic raw) {
    if (raw is List) {
      return <String, dynamic>{
        'root_type': 'list',
        'root_len': raw.length,
      };
    }
    if (raw is! Map) {
      return <String, dynamic>{'root_type': raw.runtimeType.toString()};
    }
    final root = Map<String, dynamic>.from(raw);
    final out = <String, dynamic>{
      'root_type': 'map',
      'root_keys': root.keys.toList(growable: false),
    };
    final data = root['data'];
    if (data is List) {
      out['data_type'] = 'list';
      out['data_len'] = data.length;
      return out;
    }
    if (data is Map) {
      final dataMap = Map<String, dynamic>.from(data);
      out['data_type'] = 'map';
      out['data_keys'] = dataMap.keys.toList(growable: false);
      final listKeys = dataMap.entries
          .where((entry) => entry.value is List)
          .map((entry) => entry.key)
          .toList(growable: false);
      if (listKeys.isNotEmpty) {
        out['data_list_keys'] = listKeys;
      }
      return out;
    }
    out['data_type'] = data.runtimeType.toString();
    return out;
  }

  void _logPostLoginStage({
    required String stage,
    required String outcome,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) {
    final payload = <String, dynamic>{
      'stage': stage,
      'outcome': outcome,
      ...details,
    };
    debugPrint('[KUNDI_POST_LOGIN] ${jsonEncode(payload)}');

    final evaluation = _typedV2RuntimeGate.observe(
      state: _typedV2GateState,
      stage: stage,
      outcome: outcome,
      details: details,
      now: DateTime.now().toUtc(),
    );
    if (evaluation == null) {
      return;
    }
    _typedV2GateState = evaluation.state;
    if (_typedV2GateStateStudentId.isNotEmpty) {
      unawaited(_persistTypedV2GateState(provider: 'kundelik'));
    }
    debugPrint(
      '[KUNDI_POST_LOGIN] ${jsonEncode(<String, dynamic>{
            'stage': 'typed_read_stage_gate_check',
            'outcome': evaluation.decision.name,
            'gate_trigger': evaluation.trigger,
            'samples': evaluation.stats.samples,
            'failed_rate': evaluation.stats.failedRate,
            'degraded_rate': evaluation.stats.degradedRate,
            'fallback_rate': evaluation.stats.fallbackRate,
            'parity_mismatch_rate': evaluation.stats.parityMismatchRate,
            'severe_parity_mismatch_rate':
                evaluation.stats.severeParityMismatchRate,
            'snapshot_inconsistency_count':
                evaluation.stats.snapshotInconsistencyCount,
            'profile_p95_latency_ms': evaluation.stats.profileP95LatencyMs,
            'results_p95_latency_ms': evaluation.stats.resultsP95LatencyMs,
            'overview_p95_latency_ms': evaluation.stats.overviewP95LatencyMs,
          })}',
    );
  }

  String _redactLogin(String login) {
    final normalized = login.trim();
    if (normalized.isEmpty) {
      return '<empty>';
    }
    if (normalized.length <= 2) {
      return '${normalized[0]}***';
    }
    return '${normalized.substring(0, 2)}***';
  }

  String _detectDateFormat(String raw) {
    final sample = raw.trim();
    if (sample.isEmpty) {
      return 'empty';
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(sample)) {
      return 'yyyy-mm-dd';
    }
    if (RegExp(r'^\d{1,2}[.\-/]\d{1,2}[.\-/]\d{4}$').hasMatch(sample)) {
      return 'dmy';
    }
    if (int.tryParse(sample) != null) {
      return 'unix';
    }
    if (DateTime.tryParse(sample) != null) {
      return 'datetime';
    }
    return 'other';
  }

  Map<String, String> _extractLessonPayloadSample(
      Map<String, dynamic> payload) {
    final lessonsRaw = payload['lessons'];
    if (lessonsRaw is! List || lessonsRaw.isEmpty || lessonsRaw.first is! Map) {
      return const <String, String>{
        'date_sample': '',
        'start_time_sample': '',
        'end_time_sample': '',
      };
    }
    final first = Map<String, dynamic>.from(lessonsRaw.first as Map);
    return <String, String>{
      'date_sample': (first['date'] ?? '').toString(),
      'start_time_sample': (first['start_time'] ?? '').toString(),
      'end_time_sample': (first['end_time'] ?? '').toString(),
    };
  }

  String _detectTimeFormat(String raw) {
    final sample = raw.trim();
    if (sample.isEmpty) {
      return 'empty';
    }
    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(sample)) {
      return 'hh:mm';
    }
    if (RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(sample)) {
      return 'hh:mm:ss';
    }
    return 'other';
  }

  String _sanitizeError(String message) {
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 180) {
      return normalized;
    }
    return '${normalized.substring(0, 180)}...';
  }

  void _logAuthSessionPersisted(AuthSession session) {
    _logPostLoginStage(
      stage: 'auth_session_persisted',
      outcome: 'success',
      details: {
        'has_student_id': session.studentId.trim().isNotEmpty,
        'has_access_token': session.accessToken.trim().isNotEmpty,
        'has_refresh_token': session.refreshToken.trim().isNotEmpty,
        'has_expires_at':
            session.expiresAt.toUtc().toIso8601String().isNotEmpty,
      },
    );
  }

  String _string(Object? value) => (value ?? '').toString().trim();

  String _buildTraceId(String studentId) {
    final sid = studentId.trim();
    final suffix = sid.isEmpty
        ? 'unknown'
        : sid.substring(0, sid.length >= 8 ? 8 : sid.length);
    return 'tr-${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix';
  }

  ReadSourceMode _resolvedReadMode({required String studentId}) {
    final normalizedStudentId = studentId.trim().toLowerCase();
    final cached = _typedV2CohortDecision;
    if (cached != null && cached.studentId == normalizedStudentId) {
      return cached.mode;
    }
    _typedV2CohortDecision =
        _readSourcePolicy.typedV2Decision(studentId: studentId);
    return _typedV2CohortDecision!.mode;
  }

  String _stableStudentHash(String normalizedStudentId) {
    if (normalizedStudentId.isEmpty) {
      return 'empty';
    }
    var hash = 2166136261;
    for (final unit in normalizedStudentId.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    final hex = hash.toRadixString(16).padLeft(8, '0');
    return hex.substring(0, 6);
  }

  Future<void> _hydrateTypedV2GateState({
    required String studentId,
    required String provider,
  }) async {
    final normalizedStudentId = studentId.trim().toLowerCase();
    final normalizedProvider = provider.trim().toLowerCase();
    _typedV2GateStateStudentId = normalizedStudentId;
    if (normalizedStudentId.isEmpty || normalizedProvider != 'kundelik') {
      _typedV2GateState = TypedV2GateRuntimeState.empty();
      return;
    }
    final raw = await _canonicalCacheStore.getTypedV2GateState(
      studentId: normalizedStudentId,
      provider: normalizedProvider,
    );
    final restored = _typedV2RuntimeGate.deserializeState(raw);
    _typedV2GateState = _typedV2RuntimeGate.trimState(
      state: restored,
      now: DateTime.now().toUtc(),
    );
  }

  Future<void> _persistTypedV2GateState({
    required String provider,
  }) async {
    final normalizedStudentId = _typedV2GateStateStudentId.trim().toLowerCase();
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedStudentId.isEmpty || normalizedProvider != 'kundelik') {
      return;
    }
    final trimmed = _typedV2RuntimeGate.trimState(
      state: _typedV2GateState,
      now: DateTime.now().toUtc(),
    );
    _typedV2GateState = trimmed;
    await _canonicalCacheStore.putTypedV2GateState(
      studentId: normalizedStudentId,
      provider: normalizedProvider,
      payload: _typedV2RuntimeGate.serializeState(trimmed),
    );
  }

  List<Map<String, dynamic>> _filterV1Lessons(
    List<dynamic> lessons,
    String windowFrom,
    String windowTo,
  ) {
    return lessons
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
      final date = _extractYmd(item['date']);
      return _isInWindow(date, windowFrom, windowTo);
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _filterV1Attendance(
    List<dynamic> attendance,
    String windowFrom,
    String windowTo,
  ) {
    return attendance
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
      final date = _extractYmd(item['date']);
      return _isInWindow(date, windowFrom, windowTo);
    }).toList(growable: false);
  }

  Set<String> _buildV1ResultIdentityKeys({
    required List<dynamic> lessons,
    required List<dynamic> grades,
    required String windowFrom,
    required String windowTo,
  }) {
    final out = <String>{};
    for (final raw in lessons.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final date = _extractYmd(item['date']);
      if (!_isInWindow(date, windowFrom, windowTo)) {
        continue;
      }
      final value = _string(item['grade_value']);
      if (value.isEmpty) {
        continue;
      }
      final subject = _normalizeToken(item['subject_name']);
      out.add('regular|$subject|$date|$value');
    }
    for (final raw in grades.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final kind = _normalizeToken(item['grade_type']);
      if (kind != 'sor' && kind != 'soch') {
        continue;
      }
      final date = _extractYmd(item['created_at']);
      if (!_isInWindow(date, windowFrom, windowTo)) {
        continue;
      }
      final value = _string(item['value']);
      if (value.isEmpty) {
        continue;
      }
      out.add('$kind|*|$date|$value');
    }
    return out;
  }

  Set<String> _buildV2ResultIdentityKeys(List<dynamic> results) {
    final out = <String>{};
    for (final raw in results.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final kind = _normalizeToken(item['result_kind']);
      final date = _extractYmd(item['recorded_on']);
      final value = _string(item['value_text']);
      if (date.isEmpty || value.isEmpty) {
        continue;
      }
      if (kind == 'regular') {
        out.add(
            'regular|${_normalizeToken(item['subject_name'])}|$date|$value');
      } else if (kind == 'sor' || kind == 'soch') {
        out.add('$kind|*|$date|$value');
      }
    }
    return out;
  }

  Set<String> _buildV1AggregateKeys({
    required List<dynamic> grades,
    required String windowFrom,
    required String windowTo,
  }) {
    final out = <String>{};
    for (final raw in grades.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final kind = _normalizeToken(item['grade_type']);
      if (kind != 'term' && kind != 'year') {
        continue;
      }
      final date = _extractYmd(item['created_at']);
      if (!_isInWindow(date, windowFrom, windowTo)) {
        continue;
      }
      final value = _string(item['value']);
      if (value.isEmpty) {
        continue;
      }
      out.add('$kind|$date|$value');
    }
    return out;
  }

  Set<String> _buildV2AggregateKeys(List<dynamic> aggregates) {
    final out = <String>{};
    for (final raw in aggregates.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final kind = _normalizeToken(item['result_kind']);
      if (kind != 'term' && kind != 'year') {
        continue;
      }
      final date = _extractYmd(item['recorded_on']);
      final value = _string(item['value_text']);
      if (date.isEmpty || value.isEmpty) {
        continue;
      }
      out.add('$kind|$date|$value');
    }
    return out;
  }

  bool _compareMoodParity({
    required List<dynamic> v1Lessons,
    required List<dynamic> v1Grades,
    required List<dynamic> v2Results,
    required String windowFrom,
    required String windowTo,
    required bool requireIdentityMatch,
  }) {
    if (!requireIdentityMatch) {
      return true;
    }
    final v1Mood = <String, String>{};
    for (final raw in v1Lessons.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final date = _extractYmd(item['date']);
      if (!_isInWindow(date, windowFrom, windowTo)) {
        continue;
      }
      final value = _string(item['grade_value']);
      if (value.isEmpty) {
        continue;
      }
      final key =
          'regular|${_normalizeToken(item['subject_name'])}|$date|$value';
      v1Mood[key] = _normalizeMood(item['grade_mood']);
    }
    for (final raw in v1Grades.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final kind = _normalizeToken(item['grade_type']);
      if (kind != 'sor' && kind != 'soch') {
        continue;
      }
      final date = _extractYmd(item['created_at']);
      if (!_isInWindow(date, windowFrom, windowTo)) {
        continue;
      }
      final value = _string(item['value']);
      if (value.isEmpty) {
        continue;
      }
      v1Mood['$kind|*|$date|$value'] = _normalizeMood(item['mood']);
    }

    final v2Mood = <String, String>{};
    for (final raw in v2Results.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final kind = _normalizeToken(item['result_kind']);
      final date = _extractYmd(item['recorded_on']);
      final value = _string(item['value_text']);
      if (date.isEmpty || value.isEmpty) {
        continue;
      }
      if (kind == 'regular') {
        v2Mood['regular|${_normalizeToken(item['subject_name'])}|$date|$value'] =
            _normalizeMood(item['resolved_mood']);
      } else if (kind == 'sor' || kind == 'soch') {
        v2Mood['$kind|*|$date|$value'] = _normalizeMood(item['resolved_mood']);
      }
    }

    final keys = v2Mood.keys.toSet();
    if (keys.isEmpty && v1Mood.isEmpty) {
      return true;
    }
    for (final key in keys) {
      if (!v1Mood.containsKey(key)) {
        return false;
      }
      if (v1Mood[key] != v2Mood[key]) {
        return false;
      }
    }
    return true;
  }

  Map<String, int> _buildV1AttendanceStatusMap(
    List<Map<String, dynamic>> attendance,
  ) {
    final out = <String, int>{};
    for (final item in attendance) {
      final date = _extractYmd(item['date']);
      if (date.isEmpty) {
        continue;
      }
      final status = _normalizeAttendanceStatus(item['code']);
      final key = '$date|$status';
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  Map<String, int> _buildV2AttendanceStatusMap(
    List<dynamic> attendance,
  ) {
    final out = <String, int>{};
    for (final raw in attendance.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final date = _extractYmd(item['recorded_on']);
      if (date.isEmpty) {
        continue;
      }
      final status = _normalizeAttendanceStatus(item['normalized_status']);
      final key = '$date|$status';
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final value in a) {
      if (!b.contains(value)) {
        return false;
      }
    }
    return true;
  }

  bool _mapEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  String _normalizeToken(Object? value) {
    return _string(value).toLowerCase();
  }

  String _normalizeMood(Object? value) {
    final raw = _string(value).toLowerCase();
    if (raw.isEmpty) {
      return 'unknown';
    }
    return raw;
  }

  String _normalizeAttendanceStatus(Object? value) {
    final raw = _string(value).toLowerCase();
    switch (raw) {
      case 'present':
      case 'p':
      case '+':
      case 'п':
      case 'рї':
        return 'present';
      case 'absent':
      case 'a':
      case 'н':
      case 'рЅ':
        return 'absent';
      case 'late':
      case 'l':
      case 'о':
      case 'рѕ':
        return 'late';
      case 'excused':
      case 'e':
      case 'б':
      case 'р±':
        return 'excused';
      default:
        return 'unknown';
    }
  }

  String _extractYmd(Object? value) {
    final raw = _string(value);
    if (raw.isEmpty) {
      return '';
    }
    final direct = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (direct.hasMatch(raw)) {
      return raw;
    }
    final fromIso = DateTime.tryParse(raw);
    if (fromIso != null) {
      return fromIso.toUtc().toIso8601String().split('T').first;
    }
    final inline = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(raw);
    if (inline != null) {
      return inline.group(1) ?? '';
    }
    return '';
  }

  bool _isInWindow(String ymd, String windowFrom, String windowTo) {
    if (ymd.isEmpty || windowFrom.isEmpty || windowTo.isEmpty) {
      return false;
    }
    return ymd.compareTo(windowFrom) >= 0 && ymd.compareTo(windowTo) <= 0;
  }

  Map<String, dynamic> _sanitizeIngestResponse(dynamic raw) {
    if (raw is! Map) {
      return <String, dynamic>{'type': raw.runtimeType.toString()};
    }
    final root = Map<String, dynamic>.from(raw);
    final safe = <String, dynamic>{'keys': root.keys.toList(growable: false)};
    final error = root['error'];
    if (error is Map) {
      final err = Map<String, dynamic>.from(error);
      safe['error'] = <String, dynamic>{
        'code': err['code']?.toString(),
        'message': err['message']?.toString(),
      };
      if (err['details'] is Map) {
        final details = Map<String, dynamic>.from(err['details'] as Map);
        safe['error_details_keys'] = details.keys.toList(growable: false);
      }
    }
    return safe;
  }
}
