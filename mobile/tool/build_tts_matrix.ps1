param(
    [ValidateSet('A','B','C','D')][string[]]$Cases = @('A','B','C','D'),
    [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
$taskMobile = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskOutput = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $taskMobile 'build\phase2b\apks'
} else {
    [IO.Path]::GetFullPath($OutputDirectory)
}
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$previousGradleOpts = $env:GRADLE_OPTS
$previousTts = $env:ENABLE_KUNDI_TTS
$previousVoice = $env:ENABLE_KUNDI_VOICE_INPUT
$previousAvatar = $env:ENABLE_KUNDI_HOME_REALTIME_AVATAR
$env:GRADLE_OPTS = '-Dorg.gradle.jvmargs=-Xmx3g'
$matrix = @(
    @{Name='A'; Assistant='false'; Voice='false'; Tts='false'; Avatar='false'},
    @{Name='B'; Assistant='true'; Voice='true'; Tts='false'; Avatar='true'},
    @{Name='C'; Assistant='true'; Voice='true'; Tts='true'; Avatar='false'},
    @{Name='D'; Assistant='true'; Voice='true'; Tts='true'; Avatar='true'}
)
Push-Location $taskMobile
try {
    foreach ($item in $matrix) {
        if ($item.Name -notin $Cases) { continue }
        $env:ENABLE_KUNDI_TTS = $item.Tts
        $env:ENABLE_KUNDI_VOICE_INPUT = $item.Voice
        $env:ENABLE_KUNDI_HOME_REALTIME_AVATAR = $item.Avatar
        $taskLog = Join-Path $taskOutput ($item.Name + '.build.log')
        Write-Output "Building matrix $($item.Name)"
        & flutter build apk --release --target-platform android-arm64 --target lib/main.dart `
            "--dart-define=ENABLE_KUNDI_ASSISTANT=$($item.Assistant)" `
            "--dart-define=ENABLE_KUNDI_VOICE_INPUT=$($item.Voice)" `
            "--dart-define=ENABLE_KUNDI_TTS=$($item.Tts)" `
            "--dart-define=ENABLE_KUNDI_HOME_REALTIME_AVATAR=$($item.Avatar)" *> $taskLog
        if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $taskLog -Tail 50; throw "Matrix $($item.Name) failed" }
        $apk = Join-Path $taskOutput ($item.Name + '.apk')
        Copy-Item -LiteralPath (Join-Path $taskMobile 'build\app\outputs\flutter-apk\app-release.apk') -Destination $apk -Force
        $zip = [IO.Compression.ZipFile]::OpenRead($apk)
        try {
            $entries = @($zip.Entries.FullName)
            $azure = @($entries | Where-Object { $_ -match 'libMicrosoft.CognitiveServices.Speech.*\.so$' })
            $filament = @($entries | Where-Object { $_ -match '(filament|gltfio).*\.so$' })
            $glb = @($entries | Where-Object { $_ -match '\.glb$' })
            if (($azure.Count -gt 0) -ne ($item.Tts -eq 'true')) { throw 'Azure packaging gate failed' }
            if (($filament.Count -gt 0) -ne ($item.Avatar -eq 'true')) { throw 'Filament packaging gate failed' }
            if ($glb.Count -ne [int]($item.Avatar -eq 'true')) { throw 'GLB packaging gate failed' }
            if (@($entries | Where-Object { $_ -match '(?i)unity' }).Count -gt 0) { throw 'Unity packaging gate failed' }
            if (@($entries | Where-Object { $_ -match '^lib/(?!arm64-v8a/)' }).Count -gt 0) { throw 'Unexpected ABI packaged' }
            $sdkClasses = $false
            $ttsChannel = $false
            foreach ($dex in $zip.Entries | Where-Object { $_.FullName -match '^classes\d*\.dex$' }) {
                $reader = [IO.StreamReader]::new($dex.Open(), [Text.Encoding]::Latin1)
                try {
                    $dexText = $reader.ReadToEnd()
                    if ($dexText.Contains('com/microsoft/cognitiveservices/speech')) { $sdkClasses = $true }
                    if ($dexText.Contains('kundi/tts/commands')) { $ttsChannel = $true }
                }
                finally { $reader.Dispose() }
            }
            if ($sdkClasses -ne ($item.Tts -eq 'true')) { throw 'SDK classes packaging gate failed' }
            if ($ttsChannel -ne ($item.Tts -eq 'true')) { throw 'TTS native channel registration gate failed' }
            if ($item.Tts -eq 'true' -and $azure.Count -ne 4) { throw 'Unexpected Azure native library set' }
            $report = [ordered]@{ case=$item.Name; bytes=(Get-Item -LiteralPath $apk).Length;
                sha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash;
                azureLibraries=$azure; sdkClasses=$sdkClasses; ttsNativeChannel=$ttsChannel; filamentLibraries=$filament; glb=$glb }
            $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskOutput ($item.Name + '.audit.json'))
            Write-Output "Matrix $($item.Name) PASS bytes=$($report.bytes) azureLibs=$($azure.Count) glb=$($glb.Count)"
        } finally { $zip.Dispose() }
    }
} finally {
    $env:GRADLE_OPTS = $previousGradleOpts
    $env:ENABLE_KUNDI_TTS = $previousTts
    $env:ENABLE_KUNDI_VOICE_INPUT = $previousVoice
    $env:ENABLE_KUNDI_HOME_REALTIME_AVATAR = $previousAvatar
    Pop-Location
}
