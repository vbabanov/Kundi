param(
  [string]$Workspace = "D:\Kundi",
  [string]$InputLog = "D:\Kundi\reports\stage0_flutter.log"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $InputLog)) {
  throw "Input log not found: $InputLog"
}

$reportsDir = Join-Path $Workspace "reports"
if (!(Test-Path $reportsDir)) {
  New-Item -ItemType Directory -Path $reportsDir | Out-Null
}

$outFile = Join-Path $reportsDir "stage0_telemetry_extract.log"
$patterns = @(
  "typed_read_refresh_start",
  "typed_read_refresh_result",
  "typed_read_refresh_coalesced",
  "typed_read_v2_request_profile",
  "typed_read_v2_request_results",
  "typed_read_v2_request_overview",
  "typed_read_v2_degraded_refresh",
  "typed_read_v2_failed",
  "typed_read_parity_shadow",
  "typed_read_v2_snapshot_inconsistency"
)

if (Test-Path $outFile) { Remove-Item $outFile -Force }
New-Item -ItemType File -Path $outFile -Force | Out-Null

$regex = ($patterns -join "|")
$matches = Select-String -Path $InputLog -Pattern $regex | ForEach-Object {
  $_.Line
}
if ($matches.Count -gt 0) {
  $matches | Set-Content -Path $outFile -Encoding UTF8
}

Write-Host "Extracted telemetry saved to: $outFile"
Write-Host "Quick refresh result lines:"
Select-String -Path $outFile -Pattern "typed_read_refresh_result" | ForEach-Object { $_.Line }
