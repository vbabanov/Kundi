# Typed V2 Stage 1 Execution (Practical Canary)

## Scope
- Manual-first Stage 1 start only (1-2% equivalent cohort).
- No backend contract changes.
- No auto-promote or auto-rollback.
- `schoolapp` and `8081` are out of scope.

## Delivery Path (Current)
- Mobile canary delivery is direct APK install to tester devices (`adb install -r`).
- Stage 1 canary is controlled by typed v2 cohort defines baked into the canary build.

## Stage 1 Model
- Use explicit allowlist for first canary wave (single tester group).
- Keep `TYPED_V2_COHORT_PERCENT=0`.
- Membership is explicit and reversible:
  - in cohort: IDs in `TYPED_V2_COHORT_ALLOWLIST`
  - out of cohort: all others

## Start Stage 1
1. Build canary APK:
```powershell
cd D:\Kundi\mobile
flutter build apk --debug `
  --dart-define-from-file=env/dart_define.prod.example.json `
  --dart-define=USE_TYPED_V2_READ=true `
  --dart-define=ENABLE_V2_PARITY_SHADOW=true `
  --dart-define=TYPED_V2_COHORT_PERCENT=0 `
  --dart-define=TYPED_V2_COHORT_ALLOWLIST=<comma-separated-student-ids> `
  --dart-define=TYPED_V2_COHORT_DENYLIST= `
  --dart-define=FORCE_TYPED_V2_READ=false `
  --dart-define=FORCE_LEGACY_V1_READ=false
```

2. Install to tester device:
```powershell
C:\Users\baban\AppData\Local\Android\Sdk\platform-tools\adb.exe install -r D:\Kundi\mobile\build\app\outputs\flutter-apk\app-debug.apk
```

3. Verify app-side cohort decision:
```powershell
Select-String -Path D:\Kundi\reports\stage1_flutter.log -Pattern 'typed_read_cohort_decision|typed_read_refresh_result|typed_read_stage_gate_check' | ForEach-Object { $_.Line }
```

4. Verify server-side monitoring loop:
```bash
systemctl start kundi-typed-v2-monitor.service
journalctl -u kundi-typed-v2-monitor.service -n 120 --no-pager
```

## Rollback Stage 1
Fast rollback options:
1. Ship rollback canary build with:
   - `FORCE_LEGACY_V1_READ=true`
   - `TYPED_V2_COHORT_PERCENT=0`
   - empty `TYPED_V2_COHORT_ALLOWLIST`
2. Reinstall rollback APK to canary testers.
3. Confirm `typed_read_cohort_decision` => `outcome=v1`.

## Stage 1 Started Criteria
Stage 1 is considered started only when all are true:
1. Canary APK built with cohort defines.
2. Canary APK installed on tester device(s).
3. At least one runtime log shows `typed_read_cohort_decision`.
4. Monitoring loop and Telegram alerts remain active.
