param(
    [Parameter(Mandatory = $true)][string]$SecretFile,
    [string]$ApkDirectory = (Join-Path $PSScriptRoot '..\build\phase2b\apks'),
    [ValidateSet('A', 'B', 'C', 'D')][string[]]$Cases = @('A', 'B', 'C', 'D')
)
$ErrorActionPreference = 'Stop'
# Compare real local resource keys in memory; never emit or persist their values.
$taskKeys = @()
foreach ($line in [IO.File]::ReadLines($SecretFile)) {
    $pair = ($line.Trim().TrimStart([char]0xfeff) -replace '^export\s+', '') -split '=', 2
    if ($pair.Count -eq 2 -and $pair[0].Trim() -in @('AZURE_SPEECH_KEY_PRIMARY', 'AZURE_SPEECH_KEY_SECONDARY')) {
        $value = $pair[1].Trim().Trim([char]34, [char]39)
        if ($value.Length -lt 16) { throw 'Resource key unavailable for local APK audit' }
        $taskKeys += $value
    }
}
if ($taskKeys.Count -ne 2) { throw 'Both resource keys are required for local APK audit' }
foreach ($taskCase in $Cases) {
    $taskApk = Join-Path $ApkDirectory ($taskCase + '.apk')
    $zip = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($taskApk))
    $found = $false
    try {
        foreach ($entry in $zip.Entries) {
            $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::Latin1)
            try {
                $content = $reader.ReadToEnd()
                foreach ($key in $taskKeys) {
                    $wideKey = [Text.Encoding]::Latin1.GetString([Text.Encoding]::Unicode.GetBytes($key))
                    if ($content.Contains($key) -or $content.Contains($wideKey)) { $found = $true }
                }
                $content = $null
            } finally { $reader.Dispose() }
        }
    } finally { $zip.Dispose() }
    if ($found) { throw "Matrix $taskCase contains a resource key" }
    [ordered]@{ case=$taskCase; resourceKeysPresent=$false; inspected='all decompressed entries, ASCII and UTF-16LE' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ApkDirectory ($taskCase + '.secrets-audit.json'))
    Write-Output "Matrix $taskCase resource keys absent: PASS"
}
$taskKeys = $null
$key = $null
$value = $null
$wideKey = $null
