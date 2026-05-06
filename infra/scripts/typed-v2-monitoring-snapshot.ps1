param(
  [string]$Workspace = "D:\Kundi",
  [string]$InputLog = "D:\Kundi\reports\stage0_flutter.log",
  [string]$OutputJson = "",
  [string]$OutputMarkdown = ""
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $InputLog)) {
  throw "Input log not found: $InputLog"
}

$reportsDir = Join-Path $Workspace "reports"
if (!(Test-Path $reportsDir)) {
  New-Item -ItemType Directory -Path $reportsDir | Out-Null
}

if ([string]::IsNullOrWhiteSpace($OutputJson)) {
  $OutputJson = Join-Path $reportsDir "typed_v2_monitoring_snapshot.json"
}
if ([string]::IsNullOrWhiteSpace($OutputMarkdown)) {
  $OutputMarkdown = Join-Path $reportsDir "typed_v2_monitoring_snapshot.md"
}

function Get-P95([int[]]$values) {
  if ($null -eq $values -or $values.Count -eq 0) {
    return 0
  }
  $sorted = $values | Sort-Object
  $index = [Math]::Ceiling($sorted.Count * 0.95) - 1
  if ($index -lt 0) { $index = 0 }
  if ($index -ge $sorted.Count) { $index = $sorted.Count - 1 }
  return [int]$sorted[$index]
}

function Get-Rate([int]$numerator, [int]$denominator) {
  if ($denominator -le 0) {
    return 0.0
  }
  return [Math]::Round(($numerator / $denominator), 6)
}

$stages = @(
  'typed_read_refresh_result',
  'typed_read_v2_degraded_refresh',
  'typed_read_v2_failed',
  'typed_read_parity_shadow',
  'typed_read_v2_snapshot_inconsistency',
  'typed_read_stage_gate_check'
)

$events = New-Object System.Collections.Generic.List[object]
$lineNo = 0
Get-Content -Path $InputLog | ForEach-Object {
  $lineNo++
  $line = $_
  if ($line -notmatch '\[KUNDI_POST_LOGIN\]') {
    return
  }
  $jsonStart = $line.IndexOf('{')
  if ($jsonStart -lt 0) {
    return
  }
  $jsonRaw = $line.Substring($jsonStart)
  $payload = $null
  try {
    $payload = $jsonRaw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return
  }
  if ($null -eq $payload.stage) {
    return
  }
  $stageName = $payload.stage.ToString().Trim()
  if ($stages -notcontains $stageName) {
    return
  }
  $events.Add([pscustomobject]@{
    line_no = $lineNo
    stage = $stageName
    outcome = ($payload.outcome | ForEach-Object { $_.ToString() })
    payload = $payload
  })
}

$refreshEvents = @($events | Where-Object { $_.stage -eq 'typed_read_refresh_result' })
$degradedEvents = @($events | Where-Object { $_.stage -eq 'typed_read_v2_degraded_refresh' })
$failedEvents = @($events | Where-Object { $_.stage -eq 'typed_read_v2_failed' })
$parityEvents = @($events | Where-Object { $_.stage -eq 'typed_read_parity_shadow' })
$snapshotEvents = @($events | Where-Object { $_.stage -eq 'typed_read_v2_snapshot_inconsistency' })
$gateEvents = @($events | Where-Object { $_.stage -eq 'typed_read_stage_gate_check' })

$refreshTotal = $refreshEvents.Count
$refreshSuccess = (@($refreshEvents | Where-Object { $_.payload.refresh_status -eq 'success' })).Count
$refreshDegraded = (@($refreshEvents | Where-Object { $_.payload.refresh_status -eq 'degraded' })).Count
$refreshFailed = (@($refreshEvents | Where-Object { $_.payload.refresh_status -eq 'failed' })).Count

$fallbackTotal = (@($refreshEvents | Where-Object {
  $reason = $_.payload.fallback_reason
  $null -ne $reason -and $reason.ToString().Trim() -ne ''
})).Count

$parityTotal = $parityEvents.Count
$parityMismatch = (@($parityEvents | Where-Object { $_.outcome -eq 'mismatch' })).Count
$severeParity = (@($parityEvents | Where-Object {
  $reason = $_.payload.typed_read_parity_shadow_mismatch_reason
  $null -ne $reason -and @('identity','mixed') -contains $reason.ToString().Trim()
})).Count

$profileLatencies = @($refreshEvents | ForEach-Object {
  $v = $_.payload.latency_profile_ms
  if ($null -ne $v -and [int]::TryParse($v.ToString(), [ref]([int]$null))) { [int]$v }
})
$resultsLatencies = @($refreshEvents | ForEach-Object {
  $v = $_.payload.latency_results_ms
  if ($null -ne $v -and [int]::TryParse($v.ToString(), [ref]([int]$null))) { [int]$v }
})
$overviewLatencies = @($refreshEvents | ForEach-Object {
  $v = $_.payload.latency_overview_ms
  if ($null -ne $v -and [int]::TryParse($v.ToString(), [ref]([int]$null))) { [int]$v }
})

$latestGate = if ($gateEvents.Count -gt 0) { $gateEvents[-1] } else { $null }
$gateOutcome = if ($null -ne $latestGate) { $latestGate.outcome } else { 'unknown' }
$gateTrigger = if ($null -ne $latestGate -and $null -ne $latestGate.payload.gate_trigger) { $latestGate.payload.gate_trigger.ToString() } else { 'none' }

$rollbackAlert = $false
$holdAlert = $false
$watchAlert = $false
$watchReasons = New-Object System.Collections.Generic.List[string]

if ($gateEvents.Count -eq 0) {
  $holdAlert = $true
  $watchAlert = $true
  $watchReasons.Add('no_gate_signal')
}

if ($gateOutcome -eq 'rollback') {
  $rollbackAlert = $true
} elseif ($snapshotEvents.Count -gt 0) {
  $rollbackAlert = $true
  $watchReasons.Add('snapshot_inconsistency_event_present')
}

if (-not $rollbackAlert -and $gateOutcome -eq 'hold') {
  $holdAlert = $true
}

if ($gateTrigger -eq 'insufficient_window') {
  $watchAlert = $true
  $watchReasons.Add('insufficient_sample_window')
}
if ($fallbackTotal -gt 0 -and $gateOutcome -ne 'rollback') {
  $watchAlert = $true
  $watchReasons.Add('fallback_present')
}

$sourceOfTruth = [ordered]@{
  primary = 'typed_read_stage_gate_check'
  secondary = @(
    'typed_read_refresh_result',
    'typed_read_v2_degraded_refresh',
    'typed_read_v2_failed',
    'typed_read_parity_shadow',
    'typed_read_v2_snapshot_inconsistency'
  )
  precedence = @('rollback', 'hold', 'promote')
}

$summary = [ordered]@{
  generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  input_log = $InputLog
  totals = [ordered]@{
    events_scanned = $events.Count
    refresh_total = $refreshTotal
    refresh_success = $refreshSuccess
    refresh_degraded = $refreshDegraded
    refresh_failed = $refreshFailed
    fallback_total = $fallbackTotal
    parity_total = $parityTotal
    parity_mismatch_total = $parityMismatch
    snapshot_inconsistency_total = $snapshotEvents.Count
    gate_events_total = $gateEvents.Count
  }
  rates = [ordered]@{
    failed_rate = (Get-Rate $refreshFailed $refreshTotal)
    degraded_rate = (Get-Rate $refreshDegraded $refreshTotal)
    fallback_rate = (Get-Rate $fallbackTotal $refreshTotal)
    parity_mismatch_rate = (Get-Rate $parityMismatch $parityTotal)
    severe_parity_mismatch_rate = (Get-Rate $severeParity $parityTotal)
  }
  latency_p95_ms = [ordered]@{
    profile = (Get-P95 $profileLatencies)
    results = (Get-P95 $resultsLatencies)
    overview = (Get-P95 $overviewLatencies)
  }
  gate = [ordered]@{
    latest_outcome = $gateOutcome
    latest_trigger = $gateTrigger
    latest_line_no = if ($null -ne $latestGate) { $latestGate.line_no } else { 0 }
  }
  alert_delivery = [ordered]@{
    rollback_class_active = $rollbackAlert
    hold_class_active = $holdAlert
    watch_class_active = $watchAlert
    watch_reasons = @($watchReasons)
  }
  source_of_truth = $sourceOfTruth
}

$summaryJson = $summary | ConvertTo-Json -Depth 8
$summaryJson | Set-Content -Path $OutputJson -Encoding UTF8

$md = @(
  '# Typed V2 Monitoring Snapshot',
  '',
  "- Generated (UTC): $($summary.generated_at_utc)",
  "- Input log: $InputLog",
  "- Source of truth: $($summary.source_of_truth.primary)",
  '',
  '## Latest Gate',
  "- Outcome: $gateOutcome",
  "- Trigger: $gateTrigger",
  "- Log line: $($summary.gate.latest_line_no)",
  '',
  '## Key Rates',
  "- failed_rate: $($summary.rates.failed_rate)",
  "- degraded_rate: $($summary.rates.degraded_rate)",
  "- fallback_rate: $($summary.rates.fallback_rate)",
  "- parity_mismatch_rate: $($summary.rates.parity_mismatch_rate)",
  "- severe_parity_mismatch_rate: $($summary.rates.severe_parity_mismatch_rate)",
  '',
  '## P95 Latency (ms)',
  "- profile: $($summary.latency_p95_ms.profile)",
  "- results: $($summary.latency_p95_ms.results)",
  "- overview: $($summary.latency_p95_ms.overview)",
  '',
  '## Alert Classes',
  "- rollback_class_active: $($summary.alert_delivery.rollback_class_active)",
  "- hold_class_active: $($summary.alert_delivery.hold_class_active)",
  "- watch_class_active: $($summary.alert_delivery.watch_class_active)",
  "- watch_reasons: $([string]::Join(', ', $summary.alert_delivery.watch_reasons))",
  '',
  '## Operator Action',
  '- if rollback_class_active=true: execute rollback runbook immediately',
  '- else if hold_class_active=true: freeze stage and investigate',
  '- else if latest_outcome=promote and stage window is complete: promote stage manually',
  '- else: continue monitoring in current stage'
)
$md -join "`n" | Set-Content -Path $OutputMarkdown -Encoding UTF8

Write-Host "Monitoring snapshot JSON: $OutputJson"
Write-Host "Monitoring snapshot MD:   $OutputMarkdown"
Write-Host "Latest gate outcome: $gateOutcome (trigger=$gateTrigger)"
Write-Host "Alert classes => rollback:$rollbackAlert hold:$holdAlert watch:$watchAlert"
