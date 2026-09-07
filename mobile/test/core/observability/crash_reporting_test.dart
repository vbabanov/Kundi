import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/observability/crash_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('KundiCrashReportingConfig', () {
    test('disabled reporting requires no external configuration', () {
      const config = KundiCrashReportingConfig(
        enabled: false,
        dsn: '',
        environment: '',
        release: '',
      );
      expect(
        () => config.validate(releaseMode: false),
        returnsNormally,
      );
    });

    test('enabled reporting fails closed on incomplete configuration', () {
      const config = KundiCrashReportingConfig(
        enabled: true,
        dsn: '',
        environment: 'production',
        release: '',
      );
      expect(
        () => config.validate(releaseMode: true),
        throwsA(isA<StateError>()),
      );
    });

    test('production reporting cannot run in a non-release build', () {
      const config = KundiCrashReportingConfig(
        enabled: true,
        dsn: 'https://public@example.invalid/1',
        environment: 'production',
        release: 'kundi-mobile@1.2.3+4',
      );
      expect(
        () => config.validate(releaseMode: false),
        throwsA(isA<StateError>()),
      );
      expect(
        () => config.validate(releaseMode: true),
        returnsNormally,
      );
    });

    test('staging reporting can be validated in a test build', () {
      const config = KundiCrashReportingConfig(
        enabled: true,
        dsn: 'https://public@example.invalid/1',
        environment: 'staging',
        release: 'kundi-mobile@1.2.3+4',
      );
      expect(
        () => config.validate(releaseMode: false),
        returnsNormally,
      );
    });
  });

  test('event scrubber removes user content and identifiers', () {
    final event = SentryEvent(
      message: SentryMessage('PRIVATE_MESSAGE'),
      user: SentryUser(id: 'PRIVATE_USER'),
      request: SentryRequest(data: 'PRIVATE_REQUEST'),
      breadcrumbs: [Breadcrumb(message: 'PRIVATE_BREADCRUMB')],
      tags: {'student_id': 'PRIVATE_TAG'},
      // ignore: deprecated_member_use
      extra: {'prompt': 'PRIVATE_EXTRA'},
      transaction: 'PRIVATE_TRANSACTION',
      culprit: 'PRIVATE_CULPRIT',
      exceptions: [
        SentryException(type: 'StateError', value: 'PRIVATE_EXCEPTION'),
      ],
    );

    final scrubbed = KundiCrashReporting.scrubEvent(event);
    final encoded = jsonEncode(scrubbed.toJson());
    for (final marker in <String>[
      'PRIVATE_MESSAGE',
      'PRIVATE_USER',
      'PRIVATE_REQUEST',
      'PRIVATE_BREADCRUMB',
      'PRIVATE_TAG',
      'PRIVATE_EXTRA',
      'PRIVATE_TRANSACTION',
      'PRIVATE_CULPRIT',
      'PRIVATE_EXCEPTION',
    ]) {
      expect(encoded, isNot(contains(marker)));
    }
    expect(encoded, contains('StateError'));
    expect(encoded, contains('redacted'));
  });
}
