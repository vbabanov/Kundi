# Internal Android release

The `internal` Android flavor is the private-install identity for Kundi. It is
not the future Play Store identity.

- Application ID: `com.kundi.kundi_mobile.internal`
- Backend: `https://api.kundi.lucartmax.kz`
- Assistant UI: enabled
- Voice input and TTS: disabled
- Crash reporting: disabled while no production Sentry DSN is configured
- Signing material: external to Git under `D:\Kundi-secrets\android-internal`

The stable internal-distribution certificate must be reused for private APK
updates. A future store flavor may use a separate package and a separate
production signing identity without replacing this key.

Build from the repository root with:

```powershell
.\mobile\tool\build_internal_release.ps1
```

The script validates the non-secret build-time contract, loads the encrypted
Windows-user credentials from the external secrets directory, verifies the
Gradle flavor/signing configuration, and writes the APK plus Flutter symbols to
`D:\Kundi-releases\internal`.
