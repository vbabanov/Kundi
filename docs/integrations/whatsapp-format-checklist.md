# WhatsApp Message Format Checklist

## Homework digest format
1. Must include student-context date window.
2. Must include non-empty actionable homework lines.
3. Must stay within provider length limits.
4. Should avoid unsupported markdown/HTML formatting.

## Homework photo dispatch format
1. `object_key` required.
2. attachment metadata present and valid.
3. optional text caption remains bounded.

## Validation strategy
1. Validate payload in backend before provider send.
2. Treat malformed payload as permanent failure (dead-letter path).
3. Retry only transport/provider transient errors.

## Where to tune copy
- Domain/template layer (digest builder), not worker loop.

## Staging QA checks
1. Language style is parent-friendly and concise.
2. No duplicate digest send for same idempotency key.
3. Retry path does not duplicate successful sends after recovery.
