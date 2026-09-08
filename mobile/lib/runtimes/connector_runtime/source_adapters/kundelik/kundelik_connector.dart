import 'dart:convert';

import 'package:flutter/material.dart';

import '../../anti_bot/connector_http_client.dart';
import '../../contracts/diary_connector.dart';
import '../../contracts/errors.dart';
import '../../contracts/models.dart';
import '../../diagnostics/connector_diagnostics.dart';
import '../../mappers/canonical_bundle_mapper.dart';
import '../../raw_payload/raw_payload_repository.dart';
import '../../session/connector_session_store.dart';
import 'kundelik_parsing.dart';

class KundelikConnector implements DiaryConnector {
  KundelikConnector({
    required ConnectorHttpClient client,
    required ConnectorSessionStore sessionStore,
    required RawPayloadRepository rawPayloadRepository,
    required ConnectorDiagnostics diagnostics,
    required CanonicalBundleMapper mapper,
  })  : _client = client,
        _sessionStore = sessionStore,
        _rawPayloadRepository = rawPayloadRepository,
        _diagnostics = diagnostics,
        _mapper = mapper;

  final ConnectorHttpClient _client;
  final ConnectorSessionStore _sessionStore;
  final RawPayloadRepository _rawPayloadRepository;
  final ConnectorDiagnostics _diagnostics;
  final CanonicalBundleMapper _mapper;

  DiaryAuthCredentials? _credentials;
  Map<String, String> _sourceIds = <String, String>{};
  String _latestMarksHtml = '';
  static const int _maxRetryAttempts = 3;

  @override
  Future<void> authenticate(DiaryAuthCredentials credentials) async {
    final redactedLogin = _redactLogin(credentials.login);
    _emitStageEvent(
      stage: 'authenticate_start',
      outcome: 'started',
      login: redactedLogin,
    );
    _diagnostics.record(
      'kundelik.authenticate started',
      code: 'kundelik_auth_start',
      details: {'login': redactedLogin},
    );
    _credentials = credentials;

    try {
      final bootstrapResponse = await _requestWithRetry(
        operation: 'kundelik_auth_bootstrap',
        execute: () => _client.get(
            'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic'),
      );
      _diagnostics.record(
        'kundelik.authenticate bootstrap response',
        code: 'kundelik_auth_bootstrap_result',
        details: {
          'login': redactedLogin,
          'status': bootstrapResponse.statusCode,
          'uri': _safeUriHostPath(bootstrapResponse.effectiveUri),
        },
      );
      final response = await _requestWithRetry(
        operation: 'kundelik_auth_submit',
        execute: () => _client.post(
          'https://login.kundelik.kz/login',
          data: {'login': credentials.login, 'password': credentials.password},
        ),
      );
      final status = response.statusCode;
      _rawPayloadRepository.store(
        operation: 'kundelik.authenticate',
        payload: {'status': status},
      );
      final postCookies = _extractCookies(response.headers);
      _diagnostics.record(
        'kundelik.authenticate post login response',
        code: 'kundelik_auth_submit_result',
        details: {
          'login': redactedLogin,
          'status': status,
          'uri': _safeUriHostPath(response.effectiveUri),
          'cookie_names': postCookies.keys.toList(growable: false),
          'cookie_count': postCookies.length,
        },
      );

      if (status >= 400) {
        throw ConnectorException(
          code: 'kundelik_auth_failed',
          message: 'Kundelik authentication failed',
          details: {
            'stage': 'login_post',
            'status': status,
          },
        );
      }

      final marksResponse = await _requestWithRetry(
        operation: 'kundelik_auth_verify_marks',
        execute: () => _client.get('https://kundelik.kz/marks'),
      );
      final marksStatus = marksResponse.statusCode;
      final marksOutcome = _classifyMarksOutcome(marksResponse);
      final marksRedirectedToLogin =
          marksOutcome == _KundelikMarksOutcome.redirectedToLogin;
      final marksCookies = _extractCookies(marksResponse.headers);
      final accumulatedCookies = <String, String>{}
        ..addAll(postCookies)
        ..addAll(marksCookies);
      _diagnostics.record(
        'kundelik.authenticate marks verification response',
        code: 'kundelik_auth_verify_marks_result',
        details: {
          'login': redactedLogin,
          'status': marksStatus,
          'uri': _safeUriHostPath(marksResponse.effectiveUri),
          'cookie_names': accumulatedCookies.keys.toList(growable: false),
          'cookie_count': accumulatedCookies.length,
          'redirected_to_login': marksRedirectedToLogin,
          'marks_outcome': marksOutcome.name,
        },
      );
      if (_isMarksOutcomeFailure(marksOutcome)) {
        throw ConnectorException(
          code: 'kundelik_auth_failed',
          message: 'Kundelik authentication failed',
          details: {
            'stage': 'marks_check',
            'status': marksStatus,
            'redirected_to_login': marksRedirectedToLogin,
            'marks_outcome': marksOutcome.name,
          },
        );
      }

      final cookies = accumulatedCookies
        ..putIfAbsent('__kundelik_auth_chain_verified', () => '1');

      _sessionStore.save(
        ConnectorSession(
          source: credentials.source,
          login: credentials.login,
          cookies: cookies,
          createdAt: DateTime.now().toUtc(),
        ),
      );

      _diagnostics.record(
        'kundelik.authenticate completed',
        code: 'kundelik_auth_success',
      );
      _emitStageEvent(
        stage: 'authenticate_success',
        outcome: 'success',
        login: redactedLogin,
      );
    } on ConnectorException {
      rethrow;
    } catch (error) {
      _emitStageEvent(
        stage: 'final_error_mapping',
        outcome: 'mapped_error',
        exceptionCode: 'kundelik_auth_transport_error',
        exceptionMessage: _sanitizeExceptionMessage(error.toString()),
        login: redactedLogin,
      );
      _diagnostics.record(
        'kundelik.authenticate failed',
        code: 'kundelik_auth_failed',
        level: ConnectorDiagnosticLevel.error,
        details: {
          'login': redactedLogin,
          'error': error.toString(),
        },
      );
      throw ConnectorException(
        code: 'kundelik_auth_transport_error',
        message: 'Kundelik auth transport error',
        details: {'error': error.toString()},
      );
    }
  }

  @override
  Future<Map<String, String>> bootstrapSourceIds() async {
    _requireAuthenticated();
    _emitStageEvent(
      stage: 'bootstrap_source_ids_start',
      outcome: 'started',
      schoolId: (_sourceIds['school_id'] ?? '').trim(),
      hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
      hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
      hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
      login: _redactLogin(_credentials?.login ?? ''),
    );
    _diagnostics.record(
      'kundelik.bootstrapSourceIds started',
      code: 'kundelik_bootstrap_start',
    );

    try {
      final response = await _requestWithRetry(
        operation: 'kundelik_bootstrap_source_ids',
        execute: () => _client.get('https://kundelik.kz/marks'),
      );
      final body = response.data.toString();
      _latestMarksHtml = body;
      _rawPayloadRepository.store(
        operation: 'kundelik.bootstrapSourceIds',
        payload: {'body': body},
      );

      _sourceIds = extractSourceIds(body);
      if (_sourceIds.isEmpty) {
        throw const ConnectorException(
          code: 'kundelik_source_ids_not_found',
          message: 'Unable to extract source IDs from Kundelik payload',
        );
      }
      _diagnostics.record(
        'kundelik.bootstrapSourceIds completed',
        code: 'kundelik_bootstrap_success',
        details: {
          'keys': _sourceIds.keys.toList(growable: false),
          'has_person_id': (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
          'has_school_id': (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
          'has_group_id': (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        },
      );
      _emitStageEvent(
        stage: 'bootstrap_source_ids_success',
        outcome: 'success',
        status: response.statusCode,
        uri: _safeUriHostPath(response.effectiveUri),
        schoolId: (_sourceIds['school_id'] ?? '').trim(),
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        login: _redactLogin(_credentials?.login ?? ''),
      );
      return _sourceIds;
    } on ConnectorException catch (error) {
      _emitStageEvent(
        stage: 'bootstrap_source_ids_fail',
        outcome: 'failed',
        exceptionCode: error.code,
        exceptionMessage: _sanitizeExceptionMessage(error.message),
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        login: _redactLogin(_credentials?.login ?? ''),
      );
      rethrow;
    } catch (error) {
      _emitStageEvent(
        stage: 'bootstrap_source_ids_fail',
        outcome: 'failed',
        exceptionCode: 'kundelik_source_ids_failed',
        exceptionMessage: _sanitizeExceptionMessage(error.toString()),
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        login: _redactLogin(_credentials?.login ?? ''),
      );
      _diagnostics.record(
        'kundelik.bootstrapSourceIds failed',
        code: 'kundelik_bootstrap_failed',
        level: ConnectorDiagnosticLevel.error,
        details: {'error': error.toString()},
      );
      throw ConnectorException(
        code: 'kundelik_source_ids_failed',
        message: 'Failed to bootstrap Kundelik source IDs',
        details: {'error': error.toString()},
      );
    }
  }

  @override
  Future<SourceProfile> fetchProfile() async {
    _requireAuthenticated();
    _emitStageEvent(
      stage: 'fetch_profile_start',
      outcome: 'started',
      hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
      hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
      hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
      login: _redactLogin(_credentials?.login ?? ''),
    );
    if (_sourceIds.isEmpty) {
      await bootstrapSourceIds();
    }
    try {
      final marksResponse = await _requestWithRetry(
        operation: 'kundelik_fetch_profile',
        execute: () => _client.get('https://kundelik.kz/marks'),
      );
      _latestMarksHtml = marksResponse.data.toString();
      final fallbackProfile = parseProfile(
        marksResponse.data.toString(),
        fallbackLogin: _credentials?.login ?? '',
      );

      final personId = (_sourceIds['person_id'] ?? '').trim();
      final schoolId = (_sourceIds['school_id'] ?? '').trim();
      final groupId = (_sourceIds['group_id'] ?? '').trim();

      var linksUserId = '';
      if (personId.isNotEmpty && schoolId.isNotEmpty && groupId.isNotEmpty) {
        linksUserId = await _fetchLinksUserId(
          personId: personId,
          schoolId: schoolId,
          groupId: groupId,
        );
      }

      final chatResolution = await _fetchChatIdentity(
        personId: personId,
        groupId: groupId,
        linksUserId: linksUserId,
      );

      final firstName = chatResolution.firstName.isNotEmpty
          ? chatResolution.firstName
          : fallbackProfile.firstName;
      final lastName = chatResolution.lastName.isNotEmpty
          ? chatResolution.lastName
          : fallbackProfile.lastName;
      final classLabel = chatResolution.identity.classLabel.isNotEmpty
          ? chatResolution.identity.classLabel
          : fallbackProfile.classLabel;
      final schoolName = chatResolution.identity.schoolName.isNotEmpty
          ? chatResolution.identity.schoolName
          : fallbackProfile.schoolName;
      final classTeacher = chatResolution.classTeacherFullName.isNotEmpty
          ? chatResolution.classTeacherFullName
          : fallbackProfile.classTeacherFullName;

      final profile = SourceProfile(
        firstName: firstName,
        lastName: lastName,
        gradeLevel: _extractGradeLevel(classLabel),
        classLabel: classLabel,
        schoolName: schoolName,
        classTeacherFullName: classTeacher,
      );

      _diagnostics.record(
        'kundelik.fetchProfile mapped',
        code: 'kundelik_profile_mapped',
        details: {
          'has_school_name': schoolName.trim().isNotEmpty,
          'has_class_label': classLabel.trim().isNotEmpty,
          'has_class_teacher': classTeacher.trim().isNotEmpty,
          'has_student_name':
              '${firstName.trim()} ${lastName.trim()}'.trim().isNotEmpty,
        },
      );
      _emitStageEvent(
        stage: 'fetch_profile_result',
        outcome: 'success',
        status: marksResponse.statusCode,
        uri: _safeUriHostPath(marksResponse.effectiveUri),
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        login: _redactLogin(_credentials?.login ?? ''),
      );
      return profile;
    } on ConnectorException catch (error) {
      _emitStageEvent(
        stage: 'final_error_mapping',
        outcome: 'rethrow',
        exceptionCode: error.code,
        exceptionMessage: _sanitizeExceptionMessage(error.message),
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        login: _redactLogin(_credentials?.login ?? ''),
      );
      rethrow;
    }
  }

  @override
  Future<List<SourceLesson>> fetchLessons(DateTimeRange window) async {
    _requireAuthenticated();
    _emitStageEvent(
      stage: 'fetch_lessons_start',
      outcome: 'started',
      schoolId: (_sourceIds['school_id'] ?? '').trim(),
      hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
      hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
      hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
      login: _redactLogin(_credentials?.login ?? ''),
    );
    if (_sourceIds.isEmpty) {
      await bootstrapSourceIds();
    }
    if (window.end.isBefore(window.start)) {
      throw const ConnectorException(
        code: 'kundelik_invalid_window',
        message: 'sync window end must be >= start',
      );
    }

    try {
      final personId = _sourceIds['person_id'] ?? '';
      final schoolId = _sourceIds['school_id'] ?? '';
      final groupId = _sourceIds['group_id'] ?? '';
      final query = <String, dynamic>{
        'personId': personId,
        'schoolId': schoolId,
        'startDate': window.start.toUtc().millisecondsSinceEpoch ~/ 1000,
        'finishDate': window.end.toUtc().millisecondsSinceEpoch ~/ 1000,
        'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
      };
      final response = await _requestWithRetry(
        operation: 'kundelik_fetch_lessons',
        execute: () => _client.get(
          'https://kundelik.kz/api/v2/marks/diary',
          query: query,
        ),
        retryIfStatus: (status) => status == 429 || status >= 500,
      );
      final rawCounts = _inspectDiaryCounts(response.data);
      final dayDateSamples = extractDiaryDayDateSamples(response.data);
      final diaryOutcome = _classifyDiaryOutcome(response);
      final redirectedToLogin =
          diaryOutcome == _KundelikDiaryOutcome.redirectedToLogin;
      final sessionCookies =
          _sessionStore.load()?.cookies ?? <String, String>{};
      final payloadShape = _inspectDiaryPayloadShape(response.data);
      _diagnostics.record(
        'kundelik.fetchLessons diary response',
        code: 'kundelik_fetch_lessons_result',
        details: {
          'status': response.statusCode,
          'uri': _safeUriHostPath(response.effectiveUri),
          'redirected': redirectedToLogin,
          'outcome': diaryOutcome.name,
          'query': {
            'has_person_id': personId.trim().isNotEmpty,
            'has_school_id': schoolId.trim().isNotEmpty,
            'has_group_id': groupId.trim().isNotEmpty,
            'window_utc': '${window.start.toUtc()}..${window.end.toUtc()}',
          },
          'has_days': payloadShape['has_days'],
          'has_lessons': payloadShape['has_lessons'],
          'has_subjects': payloadShape['has_subjects'],
          'raw_days_count': rawCounts['raw_days_count'],
          'raw_lessons_total_count': rawCounts['raw_lessons_total_count'],
          'raw_day_date_sample': dayDateSamples['raw_day_date_sample'],
          'normalized_day_date_sample':
              dayDateSamples['normalized_day_date_sample'],
          'cookie_count': sessionCookies.length,
          'cookie_names': sessionCookies.keys.toList(growable: false),
          'login': _redactLogin(_credentials?.login ?? ''),
        },
      );
      _emitSafeLiveLog(
        code: 'kundelik_fetch_lessons_result',
        details: {
          'status': response.statusCode,
          'uri': _safeUriHostPath(response.effectiveUri),
          'redirected': redirectedToLogin,
          'outcome': diaryOutcome.name,
          'has_person_id': personId.trim().isNotEmpty,
          'has_school_id': schoolId.trim().isNotEmpty,
          'has_group_id': groupId.trim().isNotEmpty,
          'has_days': payloadShape['has_days'],
          'has_lessons': payloadShape['has_lessons'],
          'has_subjects': payloadShape['has_subjects'],
          'raw_days_count': rawCounts['raw_days_count'],
          'raw_lessons_total_count': rawCounts['raw_lessons_total_count'],
          'raw_day_date_sample': dayDateSamples['raw_day_date_sample'],
          'normalized_day_date_sample':
              dayDateSamples['normalized_day_date_sample'],
        },
      );
      _emitStageEvent(
        stage: 'fetch_lessons_result',
        outcome: diaryOutcome.name,
        status: response.statusCode,
        uri: _safeUriHostPath(response.effectiveUri),
        schoolId: schoolId.trim(),
        hasPersonId: personId.trim().isNotEmpty,
        hasSchoolId: schoolId.trim().isNotEmpty,
        hasGroupId: groupId.trim().isNotEmpty,
        hasDays: payloadShape['has_days'] ?? false,
        hasSubjects: payloadShape['has_subjects'] ?? false,
        login: _redactLogin(_credentials?.login ?? ''),
      );

      if (diaryOutcome != _KundelikDiaryOutcome.ok) {
        throw ConnectorException(
          code: 'kundelik_fetch_lessons_failed',
          message: 'Kundelik lessons endpoint failed',
          details: {
            'status': response.statusCode,
            'outcome': diaryOutcome.name,
            'redirected': redirectedToLogin,
          },
        );
      }

      _rawPayloadRepository.store(
        operation: 'kundelik.fetchLessons',
        payload: {
          'window': '${window.start}..${window.end}',
          'body': response.data.toString(),
        },
      );

      final lessons = parseLessons(response.data);
      final mappedHomeworkCount = lessons
          .where((lesson) => lesson.homeworkText.trim().isNotEmpty)
          .length;
      final mappedGradesCount = lessons.fold<int>(
        0,
        (sum, lesson) => sum + lesson.grades.length,
      );
      _diagnostics.record(
          'kundelik.fetchLessons parsed ${lessons.length} lessons',
          code: 'kundelik_lessons_mapped',
          details: {
            'flattened_lessons_count': lessons.length,
            'mapped_homeworks_count': mappedHomeworkCount,
            'mapped_grades_count': mappedGradesCount,
            'mapped_attendance_count': 0,
          });
      _emitSafeLiveLog(
        code: 'kundelik_lesson_mapping_counts',
        details: {
          'raw_days_count': rawCounts['raw_days_count'],
          'raw_lessons_total_count': rawCounts['raw_lessons_total_count'],
          'raw_day_date_sample': dayDateSamples['raw_day_date_sample'],
          'normalized_day_date_sample':
              dayDateSamples['normalized_day_date_sample'],
          'flattened_lessons_count': lessons.length,
          'mapped_homeworks_count': mappedHomeworkCount,
          'mapped_grades_count': mappedGradesCount,
          'mapped_attendance_count': 0,
        },
      );
      return lessons;
    } on ConnectorException catch (error) {
      _emitStageEvent(
        stage: 'final_error_mapping',
        outcome: 'rethrow',
        exceptionCode: error.code,
        exceptionMessage: _sanitizeExceptionMessage(error.message),
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        login: _redactLogin(_credentials?.login ?? ''),
      );
      rethrow;
    } catch (error) {
      _diagnostics.record(
        'kundelik.fetchLessons failed',
        code: 'kundelik_lessons_failed',
        level: ConnectorDiagnosticLevel.error,
        details: {'error': error.toString()},
      );
      _emitStageEvent(
        stage: 'final_error_mapping',
        outcome: 'mapped_error',
        exceptionCode: 'kundelik_lessons_parse_failed',
        exceptionMessage: _sanitizeExceptionMessage(error.toString()),
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        login: _redactLogin(_credentials?.login ?? ''),
      );
      throw ConnectorException(
        code: 'kundelik_lessons_parse_failed',
        message: 'Failed to parse Kundelik diary lessons',
        details: {'error': error.toString()},
      );
    }
  }

  @override
  Future<List<SourceLesson>> fetchHomework(DateTimeRange window) async {
    final lessons = await fetchLessons(window);
    return lessons
        .where((lesson) => lesson.homeworkText.trim().isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<SourceGrade>> fetchGrades(DateTimeRange weekWindow) async {
    _emitStageEvent(
      stage: 'fetch_grades_start',
      outcome: 'started',
      hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
      hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
      hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
      login: _redactLogin(_credentials?.login ?? ''),
    );
    final academic = await _fetchAcademicPayload(weekWindow);
    final grades = academic.results
        .map(
          (item) => SourceGrade(
            sourceGradeKey: item.sourceResultKey,
            value: item.valueText,
            mood: item.resolvedMood,
            type: item.resultKind,
            isAbsent: item.resultKind == 'absence',
          ),
        )
        .toList(growable: false);
    _emitStageEvent(
      stage: 'fetch_grades_result',
      outcome: 'success',
      hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
      hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
      hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
      login: _redactLogin(_credentials?.login ?? ''),
    );
    _emitSafeLiveLog(
      code: 'kundelik_fetch_grades_counts',
      details: {
        'results_count': academic.results.length,
        'aggregates_count': academic.aggregates.length,
        'attendance_count': academic.attendance.length,
      },
    );
    return grades;
  }

  @override
  Future<CanonicalBundle> buildCanonicalBundle(
      DiarySyncRequest syncRequest) async {
    _emitStageEvent(
      stage: 'build_bundle_start',
      outcome: 'started',
      hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
      hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
      hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
      login: _redactLogin(_credentials?.login ?? ''),
    );
    try {
      _requireAuthenticated();
      if (syncRequest.idempotencyKey.trim().isEmpty) {
        throw const ConnectorException(
          code: 'kundelik_idempotency_required',
          message: 'idempotency key is required',
        );
      }
      if (syncRequest.to.isBefore(syncRequest.from)) {
        throw const ConnectorException(
          code: 'kundelik_invalid_sync_window',
          message: 'sync window end must be >= start',
        );
      }
      if (_sourceIds.isEmpty) {
        await bootstrapSourceIds();
      }

      final profile = await fetchProfile();
      final lessons = await fetchLessons(
          DateTimeRange(start: syncRequest.from, end: syncRequest.to));
      final academic = await _fetchAcademicPayload(
        DateTimeRange(start: syncRequest.from, end: syncRequest.to),
      );

      final bundle = _mapper.map(
        source: 'kundelik',
        account: _credentials?.login ?? '',
        idempotencyKey: syncRequest.idempotencyKey.trim(),
        sourceIds: _sourceIds,
        profile: profile,
        lessons: lessons,
        attendance: academic.attendance,
        results: academic.results,
        aggregates: academic.aggregates,
      );

      _diagnostics.record(
        'kundelik.buildCanonicalBundle completed',
        code: 'kundelik_bundle_built',
        details: {
          'lessons': lessons.length,
          'attendance': academic.attendance.length,
          'results': academic.results.length,
          'aggregates': academic.aggregates.length,
          'profile_present': true,
          'source_ids': _sourceIds.keys.toList(growable: false),
        },
      );
      _emitSafeLiveLog(
        code: 'kundelik_bundle_counts',
        details: {
          'canonical_bundle_lessons_count': lessons.length,
          'canonical_bundle_attendance_count': academic.attendance.length,
          'canonical_bundle_results_count': academic.results.length,
          'canonical_bundle_aggregates_count': academic.aggregates.length,
          'canonical_bundle_profile_present': true,
          'canonical_lesson_date_sample':
              lessons.isNotEmpty ? lessons.first.date : '',
        },
      );
      _emitStageEvent(
        stage: 'build_bundle_result',
        outcome: 'success',
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        hasDays: lessons.isNotEmpty,
        hasSubjects: lessons.any((item) => item.subjectName.trim().isNotEmpty),
        login: _redactLogin(_credentials?.login ?? ''),
      );
      return bundle;
    } on ConnectorException catch (error) {
      _emitStageEvent(
        stage: 'final_error_mapping',
        outcome: 'rethrow',
        exceptionCode: error.code,
        exceptionMessage: _sanitizeExceptionMessage(error.message),
        hasPersonId: (_sourceIds['person_id'] ?? '').trim().isNotEmpty,
        hasSchoolId: (_sourceIds['school_id'] ?? '').trim().isNotEmpty,
        hasGroupId: (_sourceIds['group_id'] ?? '').trim().isNotEmpty,
        login: _redactLogin(_credentials?.login ?? ''),
      );
      rethrow;
    }
  }

  Future<String> _fetchLinksUserId({
    required String personId,
    required String schoolId,
    required String groupId,
  }) async {
    try {
      final response = await _client.get(
        'https://kundelik.kz/api/userfeed/person/$personId/school/$schoolId/group/$groupId/links',
      );
      final raw = response.data is String
          ? response.data as String
          : jsonEncode(response.data);
      final match = RegExp(r'"userId"\s*:\s*"?(\d+)"?').firstMatch(raw);
      if (match != null) {
        return (match.group(1) ?? '').trim();
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  Future<_ChatProfileResolution> _fetchChatIdentity({
    required String personId,
    required String groupId,
    required String linksUserId,
  }) async {
    try {
      await _client.post(
        'https://kundelik.kz/chat/api/auth/credentials',
        data: const <String, dynamic>{},
      );
      final closeContactsResponse =
          await _client.get('https://kundelik.kz/chat/api/closecontacts');
      final identity = parseChatIdentity(
        closeContactsRaw: closeContactsResponse.data,
        targetGroupId: groupId,
        targetPersonId: personId,
      );
      final candidateJids = <String>{
        if (identity.classTeacherJid.trim().isNotEmpty)
          identity.classTeacherJid.trim(),
      };
      if (identity.studentJid.trim().isNotEmpty) {
        candidateJids.add(identity.studentJid.trim());
      }
      if (linksUserId.trim().isNotEmpty) {
        candidateJids.add('user_${linksUserId.trim()}@xmpp.kundelik.kz');
      }

      Map<String, String> namesByJid = const <String, String>{};
      if (candidateJids.isNotEmpty) {
        final enrichResponse = await _client.post(
          'https://kundelik.kz/chat/api/enrich',
          data: _buildEnrichBody(candidateJids.toList(growable: false)),
        );
        namesByJid = parseEnrichNames(enrichResponse.data);
      }

      final studentJid =
          _resolveStudentJid(identity: identity, linksUserId: linksUserId);
      final studentName = namesByJid[studentJid]?.trim() ?? '';
      final teacherName =
          namesByJid[identity.classTeacherJid.trim()]?.trim() ?? '';
      final (firstName, lastName) = _splitHumanName(studentName);

      _diagnostics.record(
        'kundelik.fetchProfile chat identity mapped',
        code: 'kundelik_profile_chat_identity',
        details: {
          'has_school_name': identity.schoolName.trim().isNotEmpty,
          'has_class_label': identity.classLabel.trim().isNotEmpty,
          'has_class_teacher_jid': identity.classTeacherJid.trim().isNotEmpty,
          'has_class_teacher_name': teacherName.isNotEmpty,
          'has_student_name': studentName.isNotEmpty,
        },
      );
      return _ChatProfileResolution(
        identity: identity,
        firstName: firstName,
        lastName: lastName,
        classTeacherFullName: teacherName,
      );
    } catch (error) {
      _diagnostics.record(
        'kundelik.fetchProfile chat identity fallback',
        code: 'kundelik_profile_chat_identity_fallback',
        level: ConnectorDiagnosticLevel.warning,
        details: {
          'error': _sanitizeExceptionMessage(error.toString()),
        },
      );
      return const _ChatProfileResolution(
        identity: KundelikChatIdentity(
          schoolName: '',
          classLabel: '',
          classTeacherJid: '',
          studentJid: '',
        ),
        firstName: '',
        lastName: '',
        classTeacherFullName: '',
      );
    }
  }

  String _resolveStudentJid({
    required KundelikChatIdentity identity,
    required String linksUserId,
  }) {
    if (identity.studentJid.trim().isNotEmpty) {
      return identity.studentJid.trim();
    }
    if (linksUserId.trim().isNotEmpty) {
      return 'user_${linksUserId.trim()}@xmpp.kundelik.kz';
    }
    return '';
  }

  String _buildEnrichBody(List<String> jids) {
    final out = StringBuffer();
    for (var i = 0; i < jids.length; i++) {
      final encoded = Uri.encodeQueryComponent(jids[i]);
      if (i > 0) {
        out.write('&');
      }
      out.write('jids=$encoded');
    }
    return out.toString();
  }

  (String, String) _splitHumanName(String fullName) {
    final cleaned = fullName.trim();
    if (cleaned.isEmpty) {
      return ('', '');
    }
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return (parts.first, '');
    }
    if (parts.length == 2) {
      return (parts[0], parts[1]);
    }
    return (parts[0], parts.sublist(1).join(' ').trim());
  }

  int _extractGradeLevel(String classLabel) {
    final match = RegExp(r'\d{1,2}').firstMatch(classLabel);
    if (match == null) {
      return 1;
    }
    final parsed = int.tryParse(match.group(0) ?? '');
    if (parsed == null || parsed <= 0) {
      return 1;
    }
    return parsed;
  }

  Future<_AcademicPayload> _fetchAcademicPayload(DateTimeRange window) async {
    _requireAuthenticated();
    if (_sourceIds.isEmpty) {
      await bootstrapSourceIds();
    }
    final personId = (_sourceIds['person_id'] ?? '').trim();
    final schoolId = (_sourceIds['school_id'] ?? '').trim();
    final groupId = (_sourceIds['group_id'] ?? '').trim();
    if (personId.isEmpty || schoolId.isEmpty || groupId.isEmpty) {
      throw const ConnectorException(
        code: 'kundelik_source_ids_incomplete',
        message: 'Kundelik source IDs are incomplete',
      );
    }

    if (_latestMarksHtml.trim().isEmpty) {
      final marksResponse = await _requestWithRetry(
        operation: 'kundelik_fetch_marks_for_period_ids',
        execute: () => _client.get('https://kundelik.kz/marks'),
      );
      _latestMarksHtml = marksResponse.data.toString();
    }

    final finalResponse = await _requestWithRetry(
      operation: 'kundelik_fetch_final_marks',
      execute: () => _client.get(
        'https://kundelik.kz/api/v2/marks/final/school/$schoolId/person/$personId',
        query: <String, dynamic>{
          'groupId': groupId,
          'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
      ),
    );
    _requireAcademicResponseSuccess(finalResponse, periodId: 'final');

    final periodIdsFromMarks = extractPeriodIdsFromMarksHtml(_latestMarksHtml);
    final periodIdsFromFinal = extractPeriodIdsFromMarksPayload(
      finalResponse.data,
    );
    final requestedPeriodIds = <String>[
      '',
      ...periodIdsFromMarks.where(
        (id) => id.trim().isNotEmpty && id.trim().toLowerCase() != 'final',
      ),
      ...periodIdsFromFinal.where(
        (id) => id.trim().isNotEmpty && id.trim().toLowerCase() != 'final',
      ),
    ];
    final seenPeriodIds = <String>{};
    final normalizedRequestedPeriodIds = <String>[];
    for (final id in requestedPeriodIds) {
      final normalized = id.trim();
      if (seenPeriodIds.add(normalized)) {
        normalizedRequestedPeriodIds.add(normalized);
      }
    }

    final periodPayloads = <KundelikAcademicPayload>[];
    final loadedPeriodIds = <String>[];
    for (final periodId in normalizedRequestedPeriodIds) {
      try {
        final periodResponse = await _requestWithRetry(
          operation: periodId.isEmpty
              ? 'kundelik_fetch_period_marks'
              : 'kundelik_fetch_period_marks_$periodId',
          execute: () => _client.get(
            'https://kundelik.kz/api/v2/marks/school/$schoolId/person/$personId',
            query: <String, dynamic>{
              'groupId': groupId,
              'periodId': periodId,
              'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
            },
          ),
        );
        _requireAcademicResponseSuccess(
          periodResponse,
          periodId: periodId.isEmpty ? '<current>' : periodId,
        );
        periodPayloads.add(
          parsePeriodAcademicPayload(
            periodResponse.data,
            sourceEndpoint: periodId.isEmpty ? 'period' : 'period:$periodId',
          ),
        );
        _emitSafeLiveLog(
          code: 'kundelik_period_request_result',
          details: <String, dynamic>{
            'period_id': periodId.isEmpty ? '<current>' : periodId,
            'status': periodResponse.statusCode,
            'uri': _safeUriHostPath(periodResponse.effectiveUri),
          },
        );
        loadedPeriodIds.add(periodId.isEmpty ? '<current>' : periodId);
      } catch (error) {
        if (error is ConnectorException) {
          rethrow;
        }
        throw ConnectorException(
          code: 'kundelik_fetch_period_marks_failed',
          message: 'Failed to fetch all required Kundelik period marks',
          details: <String, dynamic>{
            'period_id': periodId.isEmpty ? '<current>' : periodId,
            'error': error.toString(),
          },
        );
      }
    }

    var periodPayload = const KundelikAcademicPayload(
      results: <SourceAcademicResult>[],
      aggregates: <SourceAcademicAggregate>[],
      attendance: <SourceAttendanceEvent>[],
    );
    for (final payload in periodPayloads) {
      periodPayload = periodPayload.merge(payload);
    }
    final finalPayload = parsePeriodAcademicPayload(
      finalResponse.data,
      sourceEndpoint: 'final',
    );
    final merged = periodPayload.merge(finalPayload);

    final preDedupResults = merged.results;
    final preDedupAggregates = merged.aggregates;
    final preDedupAttendance = merged.attendance;
    final resultDedup = <String, SourceAcademicResult>{};
    for (final item in preDedupResults) {
      final key = item.sourceResultKey.isNotEmpty
          ? '${item.resultKind}|${item.sourceResultKey}'
          : '${item.resultKind}|${item.providerWorkId}|${item.providerMarkId}|${item.providerSubjectId}|${item.recordedOn}|${item.valueText}';
      resultDedup[key] = item;
    }
    final aggregateDedup = <String, SourceAcademicAggregate>{};
    for (final item in preDedupAggregates) {
      final key = item.sourceAggregateKey.isNotEmpty
          ? '${item.resultKind}|${item.sourceAggregateKey}'
          : '${item.resultKind}|${item.providerSubjectId}|${item.periodId}|${item.termNo}|${item.yearLabel}|${item.valueText}';
      aggregateDedup[key] = item;
    }
    final attendanceDedup = <String, SourceAttendanceEvent>{};
    for (final item in preDedupAttendance) {
      final key = item.sourceEventKey.isNotEmpty
          ? item.sourceEventKey
          : '${item.providerLessonRef}|${item.date}|${item.code}';
      attendanceDedup[key] = item;
    }

    final results = resultDedup.values.toList(growable: false);
    final aggregates = aggregateDedup.values.toList(growable: false);
    final attendance = attendanceDedup.values.toList(growable: false);

    final preDedupRegularCount =
        preDedupResults.where((item) => item.resultKind == 'regular').length;
    final preDedupSorCount =
        preDedupResults.where((item) => item.resultKind == 'sor').length;
    final preDedupSochCount =
        preDedupResults.where((item) => item.resultKind == 'soch').length;
    final preDedupTermCount =
        preDedupAggregates.where((item) => item.resultKind == 'term').length;
    final preDedupYearCount =
        preDedupAggregates.where((item) => item.resultKind == 'year').length;
    final regularCount =
        results.where((item) => item.resultKind == 'regular').length;
    final sorCount = results.where((item) => item.resultKind == 'sor').length;
    final sochCount = results.where((item) => item.resultKind == 'soch').length;
    final termCount =
        aggregates.where((item) => item.resultKind == 'term').length;
    final yearCount =
        aggregates.where((item) => item.resultKind == 'year').length;
    _emitSafeLiveLog(
      code: 'kundelik_fetch_academic_counts',
      details: {
        'raw_regular_count': regularCount,
        'raw_sor_count': sorCount,
        'raw_soch_count': sochCount,
        'raw_term_count': termCount,
        'raw_year_count': yearCount,
        'pre_dedup_regular_count': preDedupRegularCount,
        'pre_dedup_sor_count': preDedupSorCount,
        'pre_dedup_soch_count': preDedupSochCount,
        'pre_dedup_term_count': preDedupTermCount,
        'pre_dedup_year_count': preDedupYearCount,
        'parsed_results_count': results.length,
        'parsed_aggregates_count': aggregates.length,
        'parsed_attendance_count': attendance.length,
        'requested_period_ids_count': normalizedRequestedPeriodIds.length,
        'loaded_period_ids_count': loadedPeriodIds.length,
        'requested_period_ids_sample':
            normalizedRequestedPeriodIds.take(10).toList(growable: false),
        'loaded_period_ids_sample':
            loadedPeriodIds.take(10).toList(growable: false),
      },
    );
    _diagnostics.record(
      'kundelik.fetchGrades academic payload parsed',
      code: 'kundelik_academic_payload_parsed',
      details: {
        'regular_count': regularCount,
        'sor_count': sorCount,
        'soch_count': sochCount,
        'term_count': termCount,
        'year_count': yearCount,
        'results_count': results.length,
        'aggregates_count': aggregates.length,
        'attendance_count': attendance.length,
        'window_utc': '${window.start.toUtc()}..${window.end.toUtc()}',
      },
    );

    return _AcademicPayload(
      results: results,
      aggregates: aggregates,
      attendance: attendance,
    );
  }

  void _requireAcademicResponseSuccess(
    ConnectorHttpResponse response, {
    required String periodId,
  }) {
    final outcome = _classifyDiaryOutcome(response);
    if (outcome == _KundelikDiaryOutcome.ok) {
      return;
    }
    throw ConnectorException(
      code: 'kundelik_fetch_academic_failed',
      message: 'Kundelik academic endpoint did not return a complete payload',
      details: <String, dynamic>{
        'period_id': periodId,
        'status': response.statusCode,
        'outcome': outcome.name,
      },
    );
  }

  void _requireAuthenticated() {
    final session = _sessionStore.load();
    final credentials = _credentials;
    if (credentials == null || session == null) {
      throw const ConnectorException(
        code: 'kundelik_not_authenticated',
        message: 'KundelikConnector.authenticate() must be called first',
      );
    }
    if (session.source != credentials.source ||
        session.login.trim() != credentials.login.trim()) {
      throw const ConnectorException(
        code: 'kundelik_session_mismatch',
        message: 'Kundelik session does not match current credentials',
      );
    }
    if (!_hasRequiredCookies(session.cookies)) {
      throw const ConnectorException(
        code: 'kundelik_session_cookies_incomplete',
        message: 'Kundelik session cookies are missing or incomplete',
      );
    }
  }

  Map<String, String> _extractCookies(Map<String, List<String>> headers) {
    final out = <String, String>{};
    final rawSetCookie = headers['set-cookie'];
    if (rawSetCookie == null) {
      return out;
    }
    for (final entry in rawSetCookie) {
      final cookieParts = entry.split(';');
      if (cookieParts.isEmpty) {
        continue;
      }
      final kv = cookieParts.first.split('=');
      if (kv.length != 2) {
        continue;
      }
      final key = kv[0].trim();
      final value = kv[1].trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        out[key] = value;
      }
    }
    return out;
  }

  bool _hasRequiredCookies(Map<String, String> cookies) {
    return cookies.containsKey('__kundelik_auth_chain_verified');
  }

  bool _isRedirectedToLogin(ConnectorHttpResponse response) {
    final effectiveUri = (response.effectiveUri ?? '').toLowerCase();
    if (effectiveUri.isNotEmpty) {
      return effectiveUri.contains('login.kundelik');
    }

    // Fallback content heuristic only when final URI is unavailable.
    final body = response.data.toString().toLowerCase();
    return body.contains('login.kundelik.kz/login') ||
        body.contains('needredirect=true') ||
        body.contains('logintype=basic');
  }

  bool _isLoginPageHtml(ConnectorHttpResponse response) {
    final body = response.data.toString().toLowerCase();
    return body.contains('login.kundelik.kz/login') ||
        body.contains('name="password"') ||
        body.contains("name='password'") ||
        body.contains('logintype=basic') ||
        body.contains('needredirect=true');
  }

  bool _isAntiBotOrBlocked(ConnectorHttpResponse response) {
    final body = response.data.toString().toLowerCase();
    return body.contains('captcha') ||
        body.contains('cloudflare') ||
        body.contains('attention required') ||
        body.contains('access denied') ||
        body.contains('/cdn-cgi/');
  }

  _KundelikDiaryOutcome _classifyDiaryOutcome(ConnectorHttpResponse response) {
    final status = response.statusCode;
    if (_isRedirectedToLogin(response) || _isLoginPageHtml(response)) {
      return _KundelikDiaryOutcome.redirectedToLogin;
    }
    if (_isAntiBotOrBlocked(response)) {
      return _KundelikDiaryOutcome.blockedByAntibot;
    }
    if (status == 401) {
      return _KundelikDiaryOutcome.unauthorized;
    }
    if (status == 403) {
      return _KundelikDiaryOutcome.forbidden;
    }
    if (status == 429) {
      return _KundelikDiaryOutcome.rateLimited;
    }
    if (status >= 500) {
      return _KundelikDiaryOutcome.serverError;
    }
    if (status == 400 || (status >= 402 && status < 500)) {
      return _KundelikDiaryOutcome.badRequest;
    }
    if (status >= 200 && status < 400) {
      return _KundelikDiaryOutcome.ok;
    }
    return _KundelikDiaryOutcome.badRequest;
  }

  bool _isMarksOutcomeFailure(_KundelikMarksOutcome outcome) {
    return outcome == _KundelikMarksOutcome.redirectedToLogin ||
        outcome == _KundelikMarksOutcome.loginHtmlUnder200 ||
        outcome == _KundelikMarksOutcome.blockedByAntiBot ||
        outcome == _KundelikMarksOutcome.httpError;
  }

  _KundelikMarksOutcome _classifyMarksOutcome(ConnectorHttpResponse response) {
    final status = response.statusCode;
    if (status >= 400) {
      return _KundelikMarksOutcome.httpError;
    }
    if (_isRedirectedToLogin(response)) {
      return _KundelikMarksOutcome.redirectedToLogin;
    }
    if (_isAntiBotOrBlocked(response)) {
      return _KundelikMarksOutcome.blockedByAntiBot;
    }
    if (_isLoginPageHtml(response)) {
      return _KundelikMarksOutcome.loginHtmlUnder200;
    }
    return _KundelikMarksOutcome.marksPage;
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

  String _safeUriHostPath(String? uriRaw) {
    if (uriRaw == null || uriRaw.trim().isEmpty) {
      return '<unknown>';
    }
    final uri = Uri.tryParse(uriRaw);
    if (uri == null) {
      return '<invalid>';
    }
    return '${uri.host}${uri.path}';
  }

  Map<String, bool> _inspectDiaryPayloadShape(dynamic rawBody) {
    final dynamic parsed =
        rawBody is String ? _tryDecodeJson(rawBody) : rawBody;
    if (parsed is! Map) {
      return const <String, bool>{
        'has_days': false,
        'has_lessons': false,
        'has_subjects': false,
      };
    }
    final days = parsed['days'];
    final hasSubjectsInDays = days is List &&
        days.any((day) =>
            day is Map &&
            day['lessons'] is List &&
            (day['lessons'] as List).any((lesson) =>
                lesson is Map &&
                (lesson['subjectName'] ?? lesson['subject'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty));
    return <String, bool>{
      'has_days': parsed['days'] is List && (parsed['days'] as List).isNotEmpty,
      'has_lessons':
          parsed['lessons'] is List && (parsed['lessons'] as List).isNotEmpty,
      'has_subjects': (parsed['subjects'] is List &&
              (parsed['subjects'] as List).isNotEmpty) ||
          hasSubjectsInDays,
    };
  }

  Map<String, int> _inspectDiaryCounts(dynamic rawBody) {
    final dynamic parsed =
        rawBody is String ? _tryDecodeJson(rawBody) : rawBody;
    if (parsed is! Map) {
      return const <String, int>{
        'raw_days_count': 0,
        'raw_lessons_total_count': 0,
      };
    }
    final map = Map<String, dynamic>.from(parsed);
    final days = map['days'];
    if (days is! List) {
      final lessons = map['lessons'];
      return <String, int>{
        'raw_days_count': 0,
        'raw_lessons_total_count': lessons is List ? lessons.length : 0,
      };
    }
    var lessonsTotal = 0;
    for (final day in days) {
      if (day is! Map) {
        continue;
      }
      final rawLessons = day['lessons'];
      if (rawLessons is List) {
        lessonsTotal += rawLessons.length;
      }
    }
    return <String, int>{
      'raw_days_count': days.length,
      'raw_lessons_total_count': lessonsTotal,
    };
  }

  dynamic _tryDecodeJson(String source) {
    try {
      return source.isEmpty ? source : jsonDecode(source);
    } catch (_) {
      return source;
    }
  }

  void _emitSafeLiveLog({
    required String code,
    required Map<String, dynamic> details,
  }) {
    debugPrint('[KUNDI_LIVE][$code] ${jsonEncode(details)}');
  }

  void _emitStageEvent({
    required String stage,
    required String outcome,
    int? status,
    String? uri,
    String? schoolId,
    bool? hasPersonId,
    bool? hasSchoolId,
    bool? hasGroupId,
    bool? hasDays,
    bool? hasSubjects,
    String? exceptionCode,
    String? exceptionMessage,
    String? login,
  }) {
    final details = <String, dynamic>{
      'stage': stage,
      'outcome': outcome,
      if (status != null) 'status': status,
      if (uri != null) 'uri': uri,
      if (schoolId != null) 'school_id': schoolId,
      if (hasPersonId != null) 'has_person_id': hasPersonId,
      if (hasSchoolId != null) 'has_school_id': hasSchoolId,
      if (hasGroupId != null) 'has_group_id': hasGroupId,
      if (hasDays != null) 'has_days': hasDays,
      if (hasSubjects != null) 'has_subjects': hasSubjects,
      if (exceptionCode != null) 'exception_code': exceptionCode,
      if (exceptionMessage != null) 'exception_message': exceptionMessage,
      if (login != null) 'login': login,
    };
    _diagnostics.record(
      'kundelik.runtime.stage',
      code: 'kundelik_stage_event',
      details: details,
    );
    _emitSafeLiveLog(
      code: 'kundelik_stage_event',
      details: details,
    );
  }

  String _sanitizeExceptionMessage(String message) {
    final singleLine = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= 180) {
      return singleLine;
    }
    return '${singleLine.substring(0, 180)}...';
  }

  Future<ConnectorHttpResponse> _requestWithRetry({
    required String operation,
    required Future<ConnectorHttpResponse> Function() execute,
    bool Function(int status)? retryIfStatus,
  }) async {
    var attempt = 0;
    Object? lastError;

    while (attempt < _maxRetryAttempts) {
      attempt++;
      try {
        final response = await execute();
        final shouldRetryStatus =
            (retryIfStatus ?? _defaultRetryIfStatus)(response.statusCode);
        if (shouldRetryStatus && attempt < _maxRetryAttempts) {
          _diagnostics.record(
            '$operation attempt $attempt retry due to status ${response.statusCode}',
            code: 'kundelik_retry_status',
            level: ConnectorDiagnosticLevel.warning,
            details: {
              'operation': operation,
              'attempt': attempt,
              'status': response.statusCode,
            },
          );
          await Future<void>.delayed(_retryDelay(attempt));
          continue;
        }
        return response;
      } catch (error) {
        lastError = error;
        final shouldRetry = attempt < _maxRetryAttempts;
        _emitStageEvent(
          stage: '${operation}_attempt_error',
          outcome: shouldRetry ? 'retrying' : 'failed',
          exceptionCode: error is ConnectorException ? error.code : null,
          exceptionMessage: _sanitizeExceptionMessage(error.toString()),
          login: _redactLogin(_credentials?.login ?? ''),
        );
        _diagnostics.record(
          '$operation attempt $attempt failed',
          code:
              shouldRetry ? 'kundelik_retry_error' : 'kundelik_request_failed',
          level: shouldRetry
              ? ConnectorDiagnosticLevel.warning
              : ConnectorDiagnosticLevel.error,
          details: {
            'operation': operation,
            'attempt': attempt,
            'error': error.toString(),
          },
        );
        if (!shouldRetry) {
          break;
        }
        await Future<void>.delayed(_retryDelay(attempt));
      }
    }

    _emitStageEvent(
      stage: operation,
      outcome: 'request_failed_after_retry',
      exceptionCode: '${operation}_request_failed',
      exceptionMessage: _sanitizeExceptionMessage(lastError.toString()),
      login: _redactLogin(_credentials?.login ?? ''),
    );
    throw ConnectorException(
      code: '${operation}_request_failed',
      message: 'Connector request failed after retry',
      details: {'operation': operation, 'error': lastError.toString()},
    );
  }

  bool _defaultRetryIfStatus(int status) => status == 429 || status >= 500;

  Duration _retryDelay(int attempt) {
    final capped = (attempt * 200).clamp(200, 1000);
    return Duration(milliseconds: capped);
  }
}

class _ChatProfileResolution {
  const _ChatProfileResolution({
    required this.identity,
    required this.firstName,
    required this.lastName,
    required this.classTeacherFullName,
  });

  final KundelikChatIdentity identity;
  final String firstName;
  final String lastName;
  final String classTeacherFullName;
}

class _AcademicPayload {
  const _AcademicPayload({
    required this.results,
    required this.aggregates,
    required this.attendance,
  });

  final List<SourceAcademicResult> results;
  final List<SourceAcademicAggregate> aggregates;
  final List<SourceAttendanceEvent> attendance;
}

enum _KundelikMarksOutcome {
  marksPage,
  redirectedToLogin,
  loginHtmlUnder200,
  blockedByAntiBot,
  httpError,
}

enum _KundelikDiaryOutcome {
  ok,
  unauthorized,
  forbidden,
  rateLimited,
  redirectedToLogin,
  blockedByAntibot,
  badRequest,
  serverError,
}
