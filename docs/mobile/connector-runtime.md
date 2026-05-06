# Connector Runtime Contracts (Verified)

## `DiaryConnector` methods
- `authenticate()`
- `bootstrapSourceIds()`
- `fetchProfile()`
- `fetchLessons(window)`
- `fetchHomework(window)`
- `fetchGrades(weekWindow)`
- `buildCanonicalBundle(syncRequest)`

## Implemented adapters
- Kundelik:
  - browser-like HTTP client usage,
  - typed connector exceptions,
  - source IDs bootstrap parsing,
  - profile/lessons parsing boundary helpers,
  - canonical bundle assembly,
  - retry-safe transport for transient `429/5xx` responses,
  - typed diagnostics events (`code`, `level`, `details`).
- Dnevnik.ru:
  - explicit `UnimplementedError` stub.
- EduPage:
  - explicit `UnimplementedError` stub.

## Boundary guarantees
- Raw payload captured only in connector runtime diagnostics storage.
  - payload is redacted/truncated and TTL-pruned (no unbounded full dumps).
- Feature UI receives only canonical data.
- Connector session is isolated from feature widgets.
  - session requires freshness + cookie completeness checks.

## Known limitations
- Kundelik parser is still partial and schema-tolerant, not full provider-parity.
- Dnevnik.ru/EduPage adapters are intentionally stubbed.
