param(
  [string]$Workspace = "D:\Kundi",
  [string]$AdbPath = "C:\Users\baban\AppData\Local\Android\Sdk\platform-tools\adb.exe",
  [string]$PackageName = "com.kundi.kundi_mobile",
  [string]$MainActivity = ".MainActivity",
  [int]$TimeoutSeconds = 420,
  [int]$PollSeconds = 2,
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$mobileDir = Join-Path $Workspace "mobile"
$reportsDir = Join-Path $Workspace "reports"
$flutterLog = Join-Path $reportsDir "stage0_flutter.log"
$fullLog = Join-Path $reportsDir "stage0_full.log"
$apkPath = Join-Path $mobileDir "build\app\outputs\flutter-apk\app-debug.apk"

if (!(Test-Path $AdbPath)) {
  throw "ADB not found: $AdbPath"
}

if (!(Test-Path $reportsDir)) {
  New-Item -ItemType Directory -Path $reportsDir | Out-Null
}

if (-not $SkipBuild) {
  Push-Location $mobileDir
  try {
    flutter build apk --debug --dart-define-from-file=env/dart_define.staging.example.json --dart-define=USE_TYPED_V2_READ=true --dart-define=ENABLE_V2_PARITY_SHADOW=true
  } finally {
    Pop-Location
  }
} elseif (!(Test-Path $apkPath)) {
  throw "APK not found for -SkipBuild mode: $apkPath"
}

& $AdbPath devices
& $AdbPath install -r $apkPath
& $AdbPath shell am force-stop $PackageName
& $AdbPath logcat -c

if (Test-Path $flutterLog) { Remove-Item $flutterLog -Force }
if (Test-Path $fullLog) { Remove-Item $fullLog -Force }

$flutterProc = Start-Process -FilePath $AdbPath -ArgumentList "logcat -v threadtime -s flutter:D *:S" -RedirectStandardOutput $flutterLog -NoNewWindow -PassThru
$fullProc = Start-Process -FilePath $AdbPath -ArgumentList "logcat -v threadtime" -RedirectStandardOutput $fullLog -NoNewWindow -PassThru

& $AdbPath shell am start -n "$PackageName/$MainActivity"

Write-Host "Stage 0 capture started."
Write-Host "Operator action required now:"
Write-Host "1) Open app on device."
Write-Host "2) Perform real login (if needed)."
Write-Host "3) Trigger explicit refresh/sync."
Write-Host "Script waits for: typed_read_refresh_result"
Write-Host "Timeout: $TimeoutSeconds sec"

$refreshPattern = 'typed_read_refresh_result'
$deadline = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
$foundRefreshResult = $false

try {
  while ((Get-Date).ToUniversalTime() -lt $deadline) {
    if (Test-Path $flutterLog) {
      if (Select-String -Path $flutterLog -Pattern $refreshPattern -Quiet) {
        $foundRefreshResult = $true
        break
      }
    }
    Start-Sleep -Seconds $PollSeconds
  }
} finally {
  if (!$flutterProc.HasExited) { Stop-Process -Id $flutterProc.Id -Force }
  if (!$fullProc.HasExited) { Stop-Process -Id $fullProc.Id -Force }
}

Write-Host "Saved:"
Write-Host " - $flutterLog"
Write-Host " - $fullLog"

if ($foundRefreshResult) {
  Write-Host "SUCCESS SIGNAL DETECTED: typed_read_refresh_result"
  exit 0
}

Write-Host "TIMEOUT: typed_read_refresh_result was not observed."
Write-Host "Stage 0 remains PARTIAL (manual login/refresh likely missing in capture window)."
exit 2
