import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

typedef KundiAppRunner = void Function();

@immutable
class KundiCrashReportingConfig {
  const KundiCrashReportingConfig({
    required this.enabled,
    required this.dsn,
    required this.environment,
    required this.release,
  });

  factory KundiCrashReportingConfig.fromEnvironment() {
    return const KundiCrashReportingConfig(
      enabled: bool.fromEnvironment(
        'KUNDI_CRASH_REPORTING_ENABLED',
        defaultValue: false,
      ),
      dsn: String.fromEnvironment('KUNDI_SENTRY_DSN'),
      environment: String.fromEnvironment(
        'KUNDI_CRASH_ENVIRONMENT',
        defaultValue: 'staging',
      ),
      release: String.fromEnvironment('KUNDI_RELEASE'),
    );
  }

  final bool enabled;
  final String dsn;
  final String environment;
  final String release;

  void validate({required bool releaseMode}) {
    if (!enabled) {
      return;
    }
    final normalizedEnvironment = environment.trim().toLowerCase();
    if (!const {'development', 'staging', 'production'}
        .contains(normalizedEnvironment)) {
      throw StateError(
        'KUNDI_CRASH_ENVIRONMENT must be development, staging, or production',
      );
    }
    final parsedDsn = Uri.tryParse(dsn.trim());
    if (parsedDsn == null ||
        !const {'http', 'https'}.contains(parsedDsn.scheme) ||
        parsedDsn.host.isEmpty ||
        parsedDsn.userInfo.isEmpty) {
      throw StateError(
        'KUNDI_SENTRY_DSN must be a valid Sentry DSN when crash reporting is enabled',
      );
    }
    if (release.trim().isEmpty) {
      throw StateError(
        'KUNDI_RELEASE is required when crash reporting is enabled',
      );
    }
    if (normalizedEnvironment == 'production' && !releaseMode) {
      throw StateError(
        'production crash reporting is allowed only in a release build',
      );
    }
  }
}

abstract final class KundiCrashReporting {
  static Future<void> run(
    KundiAppRunner appRunner, {
    KundiCrashReportingConfig? config,
    bool releaseMode = kReleaseMode,
  }) async {
    final effectiveConfig =
        config ?? KundiCrashReportingConfig.fromEnvironment();
    effectiveConfig.validate(releaseMode: releaseMode);
    if (!effectiveConfig.enabled) {
      appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options
          ..dsn = effectiveConfig.dsn.trim()
          ..environment = effectiveConfig.environment.trim().toLowerCase()
          ..release = effectiveConfig.release.trim()
          ..sampleRate = 1.0
          ..sendDefaultPii = false
          ..attachScreenshot = false
          ..maxBreadcrumbs = 0
          ..enableAutoNativeBreadcrumbs = false
          ..enablePrintBreadcrumbs = false
          ..enableUserInteractionBreadcrumbs = false
          ..recordHttpBreadcrumbs = false
          ..captureFailedRequests = false
          ..captureNativeFailedRequests = false
          ..enableLogs = false
          ..enableMetrics = false
          ..tracesSampleRate = null
          ..enableAutoPerformanceTracing = false
          ..reportPackages = false
          ..enableNativeCrashHandling = true
          ..anrEnabled = true;
        options.beforeBreadcrumb = (_, __) => null;
        options.beforeSendLog = (_) => null;
        options.beforeSendMetric = (_) => null;
        options.beforeSendTransaction = (_, __) => null;
        options.beforeSend = (event, _) => scrubEvent(event);
      },
      appRunner: appRunner,
    );
  }

  @visibleForTesting
  static SentryEvent scrubEvent(SentryEvent event) {
    event
      ..message = null
      ..user = null
      ..request = null
      ..breadcrumbs = const []
      ..tags = const {}
      // ignore: deprecated_member_use
      ..extra = const {}
      ..transaction = null
      ..culprit = null
      ..logger = null
      ..serverName = null
      ..fingerprint = null
      ..contexts = Contexts(
        operatingSystem: event.contexts.operatingSystem,
        runtimes: event.contexts.runtimes,
        app: event.contexts.app,
      );
    for (final exception in event.exceptions ?? const <SentryException>[]) {
      exception
        ..value = 'redacted'
        ..throwable = null;
    }
    return event;
  }
}
