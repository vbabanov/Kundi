# Phase 1 Implementation Pack (Canonical Academic Contract v2)

## Fixed decisions (pre-code)
1. Entity split: `academic_results` (regular/sor/soch) + `academic_aggregates` (term/year).
2. Provider is mandatory first-class field on all academic facts and evidence.
3. Mood is preserved both as canonical (`resolved_mood`) and source (`source_mood_raw`).
4. Local app profile is fully separated from provider/academic identity.
5. Dedup/merge rules are formalized and endpoint-aware (`diary` vs `period`).

## Execution order (strict)
1. ADRs + exact entity decisions.
2. Migrations `0005/0006`.
3. Ingest contracts v2.
4. Canonical merge + dedup contract rules.
5. Typed backend DTO/read model plan.
6. Mobile models + local DB + use-cases (next phase).
7. Fixtures + parity tests (next phase).
8. Cleanup map-based reads and shell modules (later phase).

## Included in this pack
- ADRs:
  - `docs/architecture/adr/0001-academic-contract-v2-entity-split.md`
  - `docs/architecture/adr/0002-result-dedup-identity-rules.md`
  - `docs/architecture/adr/0003-provider-persistence-policy.md`
  - `docs/architecture/adr/0004-mood-evidence-preservation-policy.md`
  - `docs/architecture/adr/0005-local-app-profile-separation.md`
- Field matrix:
  - `docs/backend/canonical-field-matrix-v2.md`
- Migrations:
  - `backend/migrations/0005_academic_contract_v2.sql`
  - `backend/migrations/0006_academic_contract_v2_constraints_indexes.sql`
- Ingest v2 contract (additive):
  - `backend/internal/modules/diary_ingest/contracts_v2.go`
- Typed DTO/read plan:
  - `backend/internal/contracts/academic_v2.go`
  - `docs/backend/typed-read-model-plan-v2.md`
- Strict dedup rules:
  - `docs/backend/canonical-dedup-rules-v2.md`

## Non-goals in this pack
- No switch-over of runtime ingest from v1 to v2 yet.
- No breakage of current login/runtime flow.
- No speculative result kinds beyond provider-proven baseline.
