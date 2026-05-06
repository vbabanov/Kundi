# Backend API Contracts (Verified)

## Auth
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`

## Ingest
- `POST /v1/ingest/bundle`

## Student read API
- `GET /v1/profile`
- `GET /v1/lessons`
- `GET /v1/homework`
- `GET /v1/grades`
- `GET /v1/attendance`

## Assistant
- `POST /v1/assistant/message`
  - Returns `text`, `audioUrl`, `visemes`, `avatar_emotion`, `gesture_tags`, `pedagogy_flags`, `behavior`.

## WhatsApp
- `POST /v1/whatsapp/send-homework`
- `POST /v1/whatsapp/send-photo`
  - Both endpoints enqueue idempotent jobs and return `202 Accepted` + `{job_id, created}`.

## Request/response behavior
- JSON input decoding is strict (`DisallowUnknownFields`).
- Errors are structured (`code`, `message`, optional `details`).
- Protected routes require bearer access token.
- Refresh endpoint rotates refresh tokens via session store.
- Ingest writes audit event when audit service is configured.
