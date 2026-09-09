# Kundi Gamification / Achievements v1

## Authority and versions

The backend is the only authority for activity, progress, unlocks, XP, and level.
Catalog version `1` contains 13 bounded achievements and the level threshold table.
The mobile app only records a best-effort activity heartbeat, renders the returned
projection, and acknowledges pending unlock notifications.

No gamification fact contains names, contact data, message text, school data, or
other PII. Source keys are opaque existing UUIDs.

## Durable facts

| Metric | Source of truth | Identity / filter |
| --- | --- | --- |
| Active day | `gamification_activity_days` | `(student_id, activity_date)` in configured product timezone |
| Regular grade 5 | `academic_results` copied into `gamification_facts` | canonical result UUID; `result_kind='regular' AND value_numeric=5` |
| Learning question | persisted assistant response copied into `gamification_facts` | assistant message UUID; successful provider response, policy schema v1, no ready-answer risk, no safety category, allowed learning response mode |
| Attempt check | persisted assistant response copied into `gamification_facts` | same success filters plus `response_mode='attempt_check'`; excluded from the general learning-question counter |

Reconciliation only inserts missing facts. It never deletes facts or unlocks when a
current academic snapshot is empty, so an empty/new-school-year response cannot
erase earned progress. Client retries reuse the assistant exchange and canonical
grade identity, while database primary keys make replay idempotent.

There are no homework achievements in v1. Although a
`homework_completions` table exists, the current product has no durable writer that
proves a task was completed. Grade presence, a local UI state, WhatsApp delivery,
and photo delivery are not evidence of homework completion.

## XP and levels

XP is recalculated from the ledgers on every reconciliation:

- 5 XP per distinct active day;
- 10 XP per canonical regular grade 5;
- 2 XP per successful learning question, capped at 20 XP per product-local day;
- 3 XP per successful attempt check, capped at 15 XP per product-local day;
- 25 XP per achievement unlock;
- no negative XP and no deductions for grades or attendance.

Level floors for levels 1 through 10 are:
`0, 100, 250, 500, 900, 1400, 2100, 3000, 4200, 5700` XP.
Level 10 is the bounded v1 maximum.

## Operational behavior

`GAMIFICATION_TIMEZONE` defaults to `Asia/Almaty`. Activity is at most one fact per
student per product-local date. Pull-to-refresh only reloads the projection and
does not record activity. Unlock notifications are ownership-bound and acknowledged
before the compact UI celebration; concurrent start/resume calls share one claim
operation to prevent duplicate presentation.

Migration `0012_gamification_v1.sql` is additive. The previous application release
can ignore its tables, so operational rollback is a release-pointer rollback with
the new tables retained.
