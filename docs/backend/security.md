# Backend Security Foundations (Verified)

- Signed access token auth.
- Refresh token session lifecycle in `auth_refresh_sessions`.
- Refresh rotation endpoint: `POST /v1/auth/refresh`.
- Encrypted diary credentials at rest (`source_login_ciphertext`, `source_password_ciphertext`).
- Structured validation + strict JSON decoding.
- Structured error envelopes for handlers/services.
- Audit logging for sensitive flows (`audit_log`).
- API idempotency storage (`api_idempotency_keys`) and ingest idempotency conflict detection.
- External provider credentials are read via config/env wiring (no hardcoded keys in code).

## Known limitations
- Field encryption key management is local-config based; production KMS integration still required.
- Authorization model is student-centric baseline and needs role expansion for guardians/admins.
- Provider secret storage must be moved to managed secret store (Vault/KMS/Cloud Secret Manager).
