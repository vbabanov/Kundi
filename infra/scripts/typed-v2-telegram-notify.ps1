param(
  [string]$Workspace = "D:\Kundi",
  [string]$SnapshotJson = "",
  [string]$BotToken = "",
  [string]$ChatId = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SnapshotJson)) {
  $SnapshotJson = Join-Path (Join-Path $Workspace "reports") "typed_v2_monitoring_snapshot.json"
}

if (!(Test-Path $SnapshotJson)) {
  throw "Monitoring snapshot JSON not found: $SnapshotJson"
}

if ([string]::IsNullOrWhiteSpace($BotToken)) {
  $BotToken = $env:KUNDI_TYPED_V2_TELEGRAM_BOT_TOKEN
}
if ([string]::IsNullOrWhiteSpace($ChatId)) {
  $ChatId = $env:KUNDI_TYPED_V2_TELEGRAM_CHAT_ID
}

$snapshot = Get-Content -Path $SnapshotJson -Raw | ConvertFrom-Json -ErrorAction Stop

$gateOutcome = "unknown"
if ($null -ne $snapshot.gate -and $null -ne $snapshot.gate.latest_outcome) {
  $gateOutcome = $snapshot.gate.latest_outcome.ToString()
}
$gateTrigger = "none"
if ($null -ne $snapshot.gate -and $null -ne $snapshot.gate.latest_trigger) {
  $gateTrigger = $snapshot.gate.latest_trigger.ToString()
}

$rollback = $false
$hold = $false
$watch = $false
$watchReasons = @()
if ($null -ne $snapshot.alert_delivery) {
  $rollback = [bool]$snapshot.alert_delivery.rollback_class_active
  $hold = [bool]$snapshot.alert_delivery.hold_class_active
  $watch = [bool]$snapshot.alert_delivery.watch_class_active
  if ($null -ne $snapshot.alert_delivery.watch_reasons) {
    $watchReasons = @($snapshot.alert_delivery.watch_reasons)
  }
}

$alertClass = "watch"
if ($rollback) {
  $alertClass = "rollback"
} elseif ($hold) {
  $alertClass = "hold"
} elseif ($watch) {
  $alertClass = "watch"
} elseif ($gateOutcome -eq "promote") {
  $alertClass = "promote"
}

$fallbackRate = if ($null -ne $snapshot.rates -and $null -ne $snapshot.rates.fallback_rate) { $snapshot.rates.fallback_rate } else { 0 }
$degradedRate = if ($null -ne $snapshot.rates -and $null -ne $snapshot.rates.degraded_rate) { $snapshot.rates.degraded_rate } else { 0 }
$failedRate = if ($null -ne $snapshot.rates -and $null -ne $snapshot.rates.failed_rate) { $snapshot.rates.failed_rate } else { 0 }
$parityMismatchRate = if ($null -ne $snapshot.rates -and $null -ne $snapshot.rates.parity_mismatch_rate) { $snapshot.rates.parity_mismatch_rate } else { 0 }
$snapshotIssues = if ($null -ne $snapshot.totals -and $null -ne $snapshot.totals.snapshot_inconsistency_total) { $snapshot.totals.snapshot_inconsistency_total } else { 0 }
$samples = if ($null -ne $snapshot.totals -and $null -ne $snapshot.totals.refresh_total) { $snapshot.totals.refresh_total } else { 0 }

$watchReasonText = if ($watchReasons.Count -gt 0) { [string]::Join(", ", $watchReasons) } else { "none" }
$generatedAt = if ($null -ne $snapshot.generated_at_utc) { $snapshot.generated_at_utc.ToString() } else { "unknown" }

$message = @(
  "Kundi Typed V2 Rollout Alert",
  "class=$alertClass outcome=$gateOutcome trigger=$gateTrigger",
  "samples=$samples failed_rate=$failedRate degraded_rate=$degradedRate fallback_rate=$fallbackRate",
  "parity_mismatch_rate=$parityMismatchRate snapshot_inconsistency_total=$snapshotIssues",
  "watch_reasons=$watchReasonText",
  "generated_at_utc=$generatedAt",
  "snapshot_json=$SnapshotJson"
) -join "`n"

if ($DryRun) {
  Write-Host "Dry run enabled; notification not sent."
  Write-Host "----- Notification payload -----"
  Write-Host $message
  Write-Host "--------------------------------"
  return
}

if ([string]::IsNullOrWhiteSpace($BotToken) -or [string]::IsNullOrWhiteSpace($ChatId)) {
  throw "Telegram config is missing. Set -BotToken and -ChatId, or env vars KUNDI_TYPED_V2_TELEGRAM_BOT_TOKEN and KUNDI_TYPED_V2_TELEGRAM_CHAT_ID."
}

$uri = "https://api.telegram.org/bot$BotToken/sendMessage"
$body = @{
  chat_id = $ChatId
  text = $message
}

try {
  $response = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType "application/x-www-form-urlencoded"
  if ($null -eq $response -or $response.ok -ne $true) {
    throw "Telegram API returned non-ok response."
  }
  Write-Host "Notification sent to Telegram chat: $ChatId"
  Write-Host "Alert class: $alertClass"
} catch {
  throw "Notification delivery failed: $($_.Exception.Message)"
}
