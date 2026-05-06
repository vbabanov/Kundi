# Sync Debug Surface (Controlled / Debug-only)

## Purpose
Expose internal sync signals for QA without leaking sensitive connector payloads.

## Implemented debug signals
- `syncStatusProvider`
  - pending count
  - failed count
  - last successful sync timestamp
- `syncDebugSnapshotProvider` (debug/internal use)
  - recent queue entries
  - last synced request ID
  - connector diagnostics lines (already redacted)

## Enablement
- Enabled in debug mode.
- Can be explicitly enabled via:
  - `ENABLE_DEBUG_SURFACES=true` in dart-define file.

## Guardrails
1. Do not show debug surfaces in public production builds.
2. Do not display raw connector payload in UI.
3. Redacted diagnostics only.
4. Keep queue/debug visibility behind internal QA flow.
