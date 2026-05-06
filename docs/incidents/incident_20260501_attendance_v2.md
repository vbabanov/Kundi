# Incident: attendance v2 read regression — 2026-05-01

## Stable checkpoint
- stable HEAD: 9b5ce0b
- prod release: /root/kundi-prod/releases/20260501-201727
- stable tag: stable-prod-20260501
- stable branch: stable/prod-20260501

## What broke
- После attendance contract migration `/v2/results` начал возвращать HTTP 500.
- Для пользователя это выглядело как проблема логина/refresh после очистки cache.
- Реальная причина была в backend typed v2 read path, endpoint `/v2/results`, attendance query.

## Impact
- Post-login typed v2 refresh падал.
- Mobile не мог завершить refresh success до backend hotfix.
- Н/Б/О не могли стабильно отображаться до завершения contract + read fix.

## Root cause
- SQL query в `backend/internal/modules/academic/service_v2.go` после `LEFT JOIN` использовал unqualified `student_id`.
- PostgreSQL возвращал:
  - SQLSTATE: 42702
  - error: column reference "student_id" is ambiguous
- Правильный fix:
  - `WHERE student_id = $1`
  - -> `WHERE a.student_id = $1`

## Why it took too long
- Сначала дебажили UI/mobile symptoms вместо точного backend read-query failure.
- Недостаточно подробный error logging в typed v2 read path.
- Attendance contract + migration + mobile cache + UI proof были смешаны в одном длинном workflow.
- Prod оказался частью проверки migration/read path вместо короткого staging proof.

## What fixed it
- `ff9dbad feat(attendance): add v2 matching keys to ingest and read contracts`
- `62d071b feat(attendance): persist matching keys in mobile cache and week mapping`
- `f3ffe1c fix(academic): qualify v2 read query columns`
- `9b5ce0b chore(mobile): add launcher icon source asset`

## Final proof
- `/v2/results = 200`
- `typed_read_refresh_result.refresh_status = success`
- `attendance_count = 128`
- backend attendance query outcome = success
- Н/Б/О visually confirmed in Grades -> Week
- healthz/readyz ok/ready

## Prevention rules
1. Any schema/read contract change must have staging proof before prod deploy.
2. Do not mix UI work with data-contract or migration work.
3. For typed v2 read failures, capture exact SQL/scan error before hotfix.
4. SQL queries with JOIN must qualify all shared columns by alias.
5. Migration must include:
   - backup path
   - schema proof
   - read endpoint proof
   - mobile cache proof
6. No broad prompts during incident response: one exact failure, one exact fix.
7. Keep stable tags before continuing risky work.

## Follow-ups
- Add test coverage for attendance read SQL with joined tables.
- Improve backend read error logging without leaking secrets.
- Add staging deployment checklist for v2 contract migrations.
- Add CI gate for backend typed v2 read tests.
- Continue UI reference polish only on a separate branch.
