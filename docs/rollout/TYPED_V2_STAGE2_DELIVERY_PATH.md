# Typed V2 Stage 2 Android Delivery Path (Beyond ADB)

## Status (2026-04-16)
- This document is a **future-ready prepared option**.
- It is not the active execution plan at this moment.
- Stage 2 remains intentionally deferred until real tester reach grows beyond the single anchor device.

## Purpose
Define the minimal practical Android delivery path for Stage 2 rollout when:
- Stage 1 single-device canary is green.
- Percent-based Stage 2 policy is approved.
- No second real allowlist tester is available.

This document is delivery/operations only.
It does not change backend contracts, ingest/read semantics, or rollout gate logic.

## Current Gap
Current mobile delivery is:
1. local `flutter build apk`
2. optional GitHub Actions APK artifact upload
3. `adb install -r` on one canary device

This is insufficient for real Stage 2 execution because percent rollout cannot reach new users if the build is still installed only on one ADB-attached device.

## Options (Minimal Practical Comparison)

| Option | Setup Complexity | Audience Restriction | Rollback Simplicity | Release Speed | Solo-Operator Fit |
|---|---|---|---|---|---|
| Google Play Internal Testing | Medium/High (Play Console, signing pipeline, release flow) | Strong | Medium | Medium | Acceptable but heavy for immediate unblock |
| Firebase App Distribution | Medium (Firebase project/app setup, tester groups, credentials) | Strong | Medium | Fast | Good, but requires extra external setup first |
| Manual Multi-Device APK Distribution (private tester ring) | Low | Medium/Strong (private roster + private link) | High | Fastest | Best immediate unblock path |

## Recommended Path (When Stage 2 Reopens)
Use **Manual Multi-Device APK Distribution** for Stage 2 start.

Why this remains the preferred minimal path:
1. Requires no new platform setup to start.
2. Works immediately with existing build flow.
3. Keeps rollout operator-controlled and reversible.
4. Removes paper-rollout ambiguity by requiring evidence from non-anchor devices.

## Stage 2 Config
Use these defines in the Stage 2 canary APK:

```text
USE_TYPED_V2_READ=true
ENABLE_V2_PARITY_SHADOW=true
TYPED_V2_COHORT_PERCENT=2
TYPED_V2_COHORT_ALLOWLIST=1f583b87-af32-4e2b-a336-41daa7f05133
TYPED_V2_COHORT_DENYLIST=
FORCE_TYPED_V2_READ=false
FORCE_LEGACY_V1_READ=false
```

Interpretation:
- allowlist remains the Stage 1 safety anchor
- percent model provides Stage 2 expansion beyond the single anchor tester

## Prerequisites
1. Private tester roster with at least 3 devices total:
   - 1 anchor canary device (already active)
   - 2 additional real tester devices/users
2. Private delivery channel:
   - private Telegram group, or
   - restricted cloud link with explicit tester access list
3. Operator checklist ready:
   - latest mobile gate evidence
   - latest backend adapter snapshot
   - rollback APK plan

## Operator Execution Flow
1. Build Stage 2 APK with the config above.
2. Record build fingerprint:
   - file name
   - build timestamp
   - SHA256 checksum
3. Distribute only to private tester roster (not public broadcast).
4. Collect install confirmations from non-anchor testers:
   - device model
   - install time
   - app version/build marker
5. Collect first runtime evidence from non-anchor delivery:
   - `typed_read_cohort_decision`
   - `typed_read_refresh_result`
   - `typed_read_stage_gate_check`
6. Run operator monitoring loop:
   - backend snapshot (`kundi-typed-v2-monitor.service`)
   - Telegram notification check
7. Mark Stage 2 as started only if non-anchor evidence exists.

## Stage 2 "Started" Criteria
All must be true:
1. Stage 2 APK delivered to at least one non-anchor tester device.
2. Non-anchor tester produced real runtime evidence (not anchor-only logs).
3. Monitoring/Telegram loop captured post-delivery cycle.
4. No backend rollback/hold class signal.

## Rollback
Fast rollback package:
1. Build rollback APK:
   - `TYPED_V2_COHORT_PERCENT=0`
   - keep anchor allowlist only
2. Distribute rollback APK to same private tester roster.
3. Confirm post-rollback evidence:
   - no percent-based expansion behavior
   - operator snapshot/Telegram healthy

## Evidence Bundle for Stage 2 Review
Attach:
1. Stage 2 build checksum note
2. tester install confirmations (including at least one non-anchor)
3. runtime log extract for:
   - cohort decision
   - refresh result
   - stage gate check
4. backend adapter snapshot JSON/MD
5. Telegram alert confirmation
