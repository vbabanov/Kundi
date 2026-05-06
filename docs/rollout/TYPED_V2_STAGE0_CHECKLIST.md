# Typed V2 Stage 0 Checklist (Pre-Canary)

## Scope
- Stage 0 only (staging sanity before canary).
- No feature scope, no UI redesign, no model changes.
- Run against accepted typed v2 rollout runbook.

## Preconditions
1. Build flags ready:
   - `USE_TYPED_V2_READ=true`
   - `ENABLE_V2_PARITY_SHADOW=true`
2. Staging API route availability:
   - `GET /v2/profile`
   - `GET /v2/results`
   - `GET /v2/academic/overview`
3. Device visible in `adb devices` and operator has valid login credentials.

## Stage 0 Command Sequence (Exact)

Alternative:
- `powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-stage0-smoke.ps1`
- `powershell -ExecutionPolicy Bypass -File D:\Kundi\infra\scripts\typed-v2-telemetry-extract.ps1`

### 1) Build + install
```powershell
cd D:\Kundi\mobile
flutter build apk --debug --dart-define-from-file=env/dart_define.staging.example.json --dart-define=USE_TYPED_V2_READ=true --dart-define=ENABLE_V2_PARITY_SHADOW=true
C:\Users\baban\AppData\Local\Android\Sdk\platform-tools\adb.exe devices
C:\Users\baban\AppData\Local\Android\Sdk\platform-tools\adb.exe install -r D:\Kundi\mobile\build\app\outputs\flutter-apk\app-debug.apk
```

### 2) Start clean capture before any user action
```powershell
$adb='C:\Users\baban\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$reports='D:\Kundi\reports'
$flutterLog=Join-Path $reports 'stage0_flutter.log'
$fullLog=Join-Path $reports 'stage0_full.log'
if (!(Test-Path $reports)) { New-Item -ItemType Directory -Path $reports | Out-Null }
if (Test-Path $flutterLog) { Remove-Item $flutterLog -Force }
if (Test-Path $fullLog) { Remove-Item $fullLog -Force }
& $adb shell am force-stop com.kundi.kundi_mobile
& $adb logcat -c
$p1=Start-Process -FilePath $adb -ArgumentList 'logcat -v threadtime -s flutter:D *:S' -RedirectStandardOutput $flutterLog -NoNewWindow -PassThru
$p2=Start-Process -FilePath $adb -ArgumentList 'logcat -v threadtime' -RedirectStandardOutput $fullLog -NoNewWindow -PassThru
& $adb shell am start -n com.kundi.kundi_mobile/.MainActivity
```

### 3) Deterministic smoke action (mandatory)
Do not stop capture yet.

1. Open app.
2. If logged out: perform real login.
3. If already logged in: trigger manual refresh/sync.
4. Wait until `typed_read_refresh_result` appears in `stage0_flutter.log`.

### 4) Stop capture only after refresh completion marker
```powershell
Stop-Process -Id $p1.Id -Force
Stop-Process -Id $p2.Id -Force
```

### 5) Extract required telemetry evidence
```powershell
Select-String -Path D:\Kundi\reports\stage0_flutter.log -Pattern 'typed_read_refresh_start|typed_read_refresh_result|typed_read_refresh_coalesced|typed_read_v2_request_profile|typed_read_v2_request_results|typed_read_v2_request_overview|typed_read_v2_degraded_refresh|typed_read_v2_failed|typed_read_parity_shadow|typed_read_v2_snapshot_inconsistency' | ForEach-Object { $_.Line }
```

### 6) Optional DB evidence for active snapshot
```powershell
$adb='C:\Users\baban\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$dbOut='D:\Kundi\reports\stage0_device.db'
cmd /c """$adb"" exec-out run-as com.kundi.kundi_mobile cat databases/kundi_mobile.db > ""$dbOut"""
```

## Stage 0 Pass Criteria
- `typed_read_refresh_result` exists with:
  - `read_mode=v2`
  - `refresh_status=success`
- v2 triplet called and returned 200 in the same refresh cycle:
  - `/v2/profile`
  - `/v2/results`
  - `/v2/academic/overview`
- Single-snapshot discipline:
  - one `snapshot_at` across profile/results/overview in the cycle
- No silent failure:
  - no missing completion event after refresh start
- No hard integrity signals:
  - no `typed_read_v2_failed`
  - no `typed_read_v2_snapshot_inconsistency`

## Stage 0 Evidence Package
Required:
- `D:\Kundi\reports\stage0_flutter.log`
- `D:\Kundi\reports\stage0_full.log`
- screenshots:
  - profile surface
  - grades surface
  - lessons/diary surface

Recommended:
- `D:\Kundi\reports\stage0_device.db`
