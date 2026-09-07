# Mobile crash and ANR reporting

The mobile client contains a dormant Sentry Flutter crash path. It is disabled by default and sends nothing unless all runtime values are supplied. Production mode additionally refuses to start outside a release build.

```text
KUNDI_CRASH_REPORTING_ENABLED=true
KUNDI_SENTRY_DSN=<production-project-dsn>
KUNDI_CRASH_ENVIRONMENT=production
KUNDI_RELEASE=kundi-mobile@<version>+<build>
```

The configuration keeps native crash handling and Android ANR detection enabled. It disables screenshots, breadcrumbs, failed-request capture, logs, metrics, tracing, profiling, and user-interaction telemetry. `sendDefaultPii` is false. A final event processor strips user, request, message, breadcrumb, tags, extra data, route/transaction data, and free-form exception values while retaining exception type and stack traces.

## External acceptance

A release owner must provide a dedicated production project/DSN and access to its event view. Then, using an approved internally distributed release-signed build:

1. Trigger one synthetic uncaught Dart exception with a unique non-PII marker.
2. Trigger one synthetic Android ANR using a test-only harness that is absent from the production UI.
3. Restart the app if required for native cached-event delivery.
4. Verify both events have the exact production environment and `KUNDI_RELEASE`.
5. Verify stack trace symbolication and confirm that user/request/message/breadcrumb/tag/extra fields and the privacy test marker are absent.
6. Record only event IDs, release, timestamps, and PASS/FAIL; do not export raw event payloads.

Until both events are received and inspected, mobile crash/ANR delivery is `OPEN-EXTERNAL`. A debug build or a local fake endpoint is not equivalent evidence.
