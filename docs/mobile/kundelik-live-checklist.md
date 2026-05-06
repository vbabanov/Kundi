# Kundelik Live Validation Checklist

## Scope
Validate live connector behavior on real Kundelik sessions without leaking sensitive data.

## Preconditions
1. Build mobile with staging API endpoint (`--dart-define-from-file`).
2. Test account prepared with real schedule/homework/grades.
3. Debug surfaces enabled only for QA/internal build.

## Checklist
1. Auth flow sequence
   - GET login bootstrap page is reachable
   - POST login form returns non-terminal response
   - mandatory follow-up GET `https://kundelik.kz/marks` is executed
   - `/marks` does not resolve back to login page
   - diagnostics include `kundelik_auth_bootstrap_result`, `kundelik_auth_submit_result`, `kundelik_auth_verify_marks_result`
   - diagnostics keep only redacted login and cookie names/count (no cookie values/password)
2. Session validation timing
   - session is persisted only after `/marks` verification
   - cookie map is non-empty after auth chain
   - expired session is rejected and prompts re-auth
3. Source IDs bootstrap
   - `person_id`, `school_id`, `group_id` discovered
   - missing IDs produce typed diagnostics error
4. Data fetch
   - profile fetch works after authenticated session
   - lessons fetched for selected window
   - diary diagnostics include endpoint `status`, `uri`, `outcome`, `redirected`
   - diary diagnostics include only query presence flags and cookie names/count
   - homework/grades extracted and typed
5. Bundle build
   - canonical bundle includes source IDs + profile + lessons + grades
   - idempotency key is present
6. Retry behavior
   - transient failures (429/5xx) trigger retry path
   - terminal parse/auth errors do not loop silently
7. Session stale behavior
   - stale/expired session fails fast and does not emit partial bundle

## Acceptance
- No raw sensitive data leaks to UI or logs.
- Diagnostics contain only redacted/truncated payload evidence.
- Auth success is not tied to rigid cookie-name heuristics when `/marks` verification succeeds.
