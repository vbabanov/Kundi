# Canonical Dedup Contract Rules v2

## Scope
Provider-proven baseline kinds only:
- event-level: `regular`, `sor`, `soch`
- aggregate-level: `term`, `year`

## Provider requirement
Каждое правило dedup применяется в пределах одного `provider`.
Межпровайдерный merge запрещен.

## Event-level identities (`academic_results`)

### 1) `regular`
Canonical identity priority:
1. `(provider, provider_mark_id)` if `provider_mark_id` present.
2. `(provider, source_result_key)` if present.
3. fingerprint:
   - `provider`
   - `provider_person_id`
   - `provider_subject_id`
   - `provider_work_id`
   - `value_text`
   - `recorded_on`
   - `lesson_number`

### 2) `sor` / `soch`
Canonical identity priority:
1. `(provider, provider_mark_id)` if present.
2. `(provider, provider_work_id, result_kind, provider_subject_id, term_no)`.
3. `(provider, source_result_key)`.

## Aggregate identities (`academic_aggregates`)

### 3) `term`
Identity:
- `(provider, provider_subject_id, result_kind='term', term_no, period_id)`

### 4) `year`
Identity:
- `(provider, provider_subject_id, result_kind='year', year_label)`

## Merge policy (operational)

### diary vs period (event-level)
For each incoming event-level result:
1. Build identity by kind-specific priority.
2. Lookup existing canonical row by identity in `academic_results`.
3. If row exists:
   - keep same canonical row id;
   - append evidence row with new endpoint fingerprint;
   - update canonical fields by precedence only:
     - `resolved_mood`
     - `lesson_id` (only if incoming source has higher precedence and non-empty link)
     - `provider_subject_id/subject_name` (fill missing only).
4. If row not found:
   - insert new canonical row in `academic_results`;
   - insert first evidence row.
5. If payload has no canonical field change but identity matches:
   - **evidence-only update** (new evidence row, canonical row unchanged).

### period vs year aggregate
- Never merge event-level result into aggregate-level row.
- `term/year` remain in `academic_aggregates`.

## Explicit split: regular vs SOR/SOCH
- `regular` rows use regular identity/fingerprint only.
- `sor/soch` rows use summative identity only.
- Cross-kind merge is forbidden even if value/date/subject совпадают.

## Precedence
1. `diary` > `period` for lesson linkage, lesson time/date alignment.
2. `period` may supplement missing fields (e.g. subject metadata) when diary empty.
3. `resolved_mood` comes from highest-precedence source.
4. Every source mood is preserved in `academic_result_evidence.source_mood_raw`.

## Evidence rules
- Any accepted source payload that affects an existing canonical row MUST create evidence row.
- Evidence uniqueness: `(result_id|aggregate_id, fingerprint_sha256)`.
- Evidence never deletes prior evidence entries.
