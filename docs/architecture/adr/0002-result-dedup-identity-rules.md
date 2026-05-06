# ADR 0002: Result Identity and Dedup Rules

## Status
Accepted

## Context
В Kundelik обычные оценки дублируются между `marks/diary` и `marks/school/...`.
СОР/СОЧ нельзя сливать с regular.

## Decision
Приняты отдельные identity/dedup правила:

1. `regular` identity:
   - primary: `provider_mark_id` (если есть),
   - fallback fingerprint: `provider + provider_person_id + provider_subject_id + provider_work_id + value + recorded_on + lesson_number`.
2. `sor/soch` identity:
   - primary: `provider_mark_id` или `provider_work_id + kind + subject + term_no`.
3. `term/year` identity (`academic_aggregates`):
   - `provider + provider_person_id + provider_subject_id + result_kind + term_no|year_label`.

## Merge semantics
- `diary` vs `period`:
  - совпал identity: обновляем canonical row + добавляем evidence.
  - не совпал: создаем новый canonical row.
- `regular` не merge с `sor/soch`.
- aggregate (`term/year`) живут отдельно от event-level таблицы.

## Source precedence
- `regular`: `diary` выше `period` для lesson binding/time/topic.
- `mood` при конфликте:
  - `resolved_mood` из источника с более высоким precedence,
  - все source moods сохраняются в evidence.
