[CmdletBinding()]
param(
    [string]$SecretsDirectory = 'D:\Kundi-secrets\android-internal',
    [string]$ArtifactsRoot = 'D:\Kundi-releases\internal'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$mobileDirectory = Split-Path -Parent $PSScriptRoot
$repositoryDirectory = Split-Path -Parent $mobileDirectory
$defineFile = Join-Path $mobileDirectory 'env\dart_define.internal.json'
$keystorePath = Join-Path $SecretsDirectory 'kundi-internal-distribution.jks'
$storeCredentialPath = Join-Path $SecretsDirectory 'store-password.credential.xml'
$keyCredentialPath = Join-Path $SecretsDirectory 'key-password.credential.xml'

foreach ($requiredPath in @($defineFile, $keystorePath, $storeCredentialPath, $keyCredentialPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required internal-release input is missing: $requiredPath"
    }
}

$defines = Get-Content -Raw -LiteralPath $defineFile | ConvertFrom-Json
$expectedDefines = [ordered]@{
    API_BASE_URL = 'https://api.kundi.lucartmax.kz'
    ENABLE_DEBUG_SURFACES = 'false'
    ENABLE_KUNDI_ASSISTANT = 'true'
    ENABLE_KUNDI_BEHAVIOR_CORE = 'true'
    ENABLE_KUNDI_HOME_REALTIME_AVATAR = 'true'
    ENABLE_KUNDI_VOICE_INPUT = 'true'
    ENABLE_KUNDI_TTS = 'true'
    KUNDI_CRASH_REPORTING_ENABLED = 'false'
}
foreach ($entry in $expectedDefines.GetEnumerator()) {
    if ([string]$defines.($entry.Key) -cne $entry.Value) {
        throw "Unsafe internal release define: $($entry.Key)"
    }
}

$storeCredential = Import-Clixml -LiteralPath $storeCredentialPath
$keyCredential = Import-Clixml -LiteralPath $keyCredentialPath
$storePassword = $storeCredential.GetNetworkCredential().Password
$keyPassword = $keyCredential.GetNetworkCredential().Password
if ([string]::IsNullOrWhiteSpace($storePassword) -or [string]::IsNullOrWhiteSpace($keyPassword)) {
    throw 'Internal signing credentials could not be decrypted for the current Windows user.'
}

$previousEnvironment = @{}
$environmentValues = [ordered]@{
    KUNDI_INTERNAL_ANDROID_KEYSTORE_PATH = $keystorePath
    KUNDI_INTERNAL_ANDROID_KEYSTORE_PASSWORD = $storePassword
    KUNDI_INTERNAL_ANDROID_KEY_ALIAS = 'kundi-internal-distribution'
    KUNDI_INTERNAL_ANDROID_KEY_PASSWORD = $keyPassword
    ENABLE_KUNDI_HOME_REALTIME_AVATAR = 'true'
    ENABLE_KUNDI_VOICE_INPUT = 'true'
    ENABLE_KUNDI_TTS = 'true'
}

try {
    foreach ($entry in $environmentValues.GetEnumerator()) {
        $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }

    Push-Location $mobileDirectory
    try {
        # Worktrees can otherwise reuse stale Flutter/Kotlin intermediates whose
        # recorded roots point at another checkout. Internal artifacts must be
        # compiled from the exact source SHA printed in their filename.
        & flutter clean
        if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed' }

        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

        & .\android\gradlew.bat -p android :app:verifyInternalReleaseConfiguration
        if ($LASTEXITCODE -ne 0) { throw 'Internal release verification failed' }

        $sourceSha = (& git -C $repositoryDirectory rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $sourceSha -notmatch '^[0-9a-f]{40}$') {
            throw 'Could not resolve the source commit.'
        }
        $shortSha = $sourceSha.Substring(0, 12)
        $pubspecVersionLine = Get-Content -LiteralPath (Join-Path $mobileDirectory 'pubspec.yaml') |
            Where-Object { $_ -match '^version:\s*(\S+)\s*$' } |
            Select-Object -First 1
        if ($pubspecVersionLine -notmatch '^version:\s*(\S+)\s*$') {
            throw 'Could not resolve the mobile version.'
        }
        $version = $Matches[1]
        $artifactDirectory = Join-Path $ArtifactsRoot "$version-$shortSha"
        $symbolsDirectory = Join-Path $artifactDirectory 'symbols'
        New-Item -ItemType Directory -Path $symbolsDirectory -Force | Out-Null

        & flutter build apk --flavor internal --release --target-platform android-arm64 `
            --dart-define-from-file=$defineFile `
            --split-debug-info=$symbolsDirectory
        if ($LASTEXITCODE -ne 0) { throw 'Flutter internal release build failed' }

        $builtApk = Join-Path $mobileDirectory 'build\app\outputs\flutter-apk\app-internal-release.apk'
        if (-not (Test-Path -LiteralPath $builtApk -PathType Leaf)) {
            throw "Expected APK was not produced: $builtApk"
        }
        $artifactPath = Join-Path $artifactDirectory "Kundi-internal-$version-$shortSha.apk"
        Copy-Item -LiteralPath $builtApk -Destination $artifactPath -Force
        Write-Output $artifactPath
    }
    finally {
        Pop-Location
    }
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    $storePassword = $null
    $keyPassword = $null
}
