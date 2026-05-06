# V2 Merge/Dedup Test Matrix (CI Regression Map)

## Integration tests -> guarantees

1. `TestV2DiaryThenPeriodDuplicateRegularCreatesOneCanonicalTwoEvidence`
- Rule: duplicate regular result diary+period.
- Guarantee: one canonical row, two evidences, no canonical duplication.

2. `TestV2PeriodThenDiaryDuplicateRegularDiaryPrecedenceWins`
- Rule: reverse order duplicate regular.
- Guarantee: one canonical row, diary precedence updates resolved mood/linkage.

3. `TestV2EvidenceOnlyScenarioAddsEvidenceWithoutNewCanonical`
- Rule: identity match with existing canonical row.
- Guarantee: evidence-only append, no new canonical row.

4. `TestV2NoMatchCreatesNewCanonicalRow`
- Rule: no-match scenario.
- Guarantee: new canonical row created, no false merge.

5. `TestV2SorSochSeparatedFromRegular`
- Rule: cross-kind separation.
- Guarantee: regular never merges with sor/soch.

6. `TestV2TermYearWrittenOnlyToAggregates`
- Rule: aggregate split.
- Guarantee: term/year stored in `academic_aggregates` only.

7. `TestV2MoodPrecedencePreservesBothSources`
- Rule: mood precedence.
- Guarantee: resolved mood follows `diary > period > final > unknown`; raw moods preserved in evidence.

8. `TestV2IdempotencyReplayDoesNotDuplicateCanonicalOrEvidence`
- Rule: replay/idempotency.
- Guarantee: replay is already_processed, no canonical/evidence duplication.

9. `TestV2WeakFingerprintProtectionNoFalseMerge`
- Rule: anti-collision.
- Guarantee: similar date/subject/value does not cause false merge when identity differs.

10. `TestV2RealFixturesEndToEndWriteReadConsistency`
- Rule: real payload e2e.
- Guarantee: real Kundelik payload -> bundle v2 -> ingest -> merge/evidence -> typed DTO consistency.

11. `TestV2RealPayloadKindsStayBaselineOnly`
- Rule: baseline kinds only.
- Guarantee: real fixtures map only to `regular/sor/soch/term/year`.

12. `TestV2SQLConstraintsWithRealPostgresIfConfigured`
- Rule: SQL semantics check.
- Guarantee: unique/check constraints enforce dedup identities and dimension rules at database level.
- Note: skipped automatically if `TEST_DATABASE_URL` is not configured.
