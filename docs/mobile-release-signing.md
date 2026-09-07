# Android release signing identities

Kundi release builds must never use Android's debug signing identity. The
private `internal` flavor has a stable internal-distribution identity. The
future Play Store identity remains intentionally undefined and must be
separate.

## Internal distribution

The local release script loads the private signing material from
`D:\Kundi-secrets\android-internal`. Gradle receives these four process-only
environment variables:

- `KUNDI_INTERNAL_ANDROID_KEYSTORE_PATH`
- `KUNDI_INTERNAL_ANDROID_KEYSTORE_PASSWORD`
- `KUNDI_INTERNAL_ANDROID_KEY_ALIAS`
- `KUNDI_INTERNAL_ANDROID_KEY_PASSWORD`

Do not commit a keystore, passwords, a populated properties file, or command output containing these values. Partial configuration fails during Gradle configuration. A configured keystore path must resolve to a readable file.

Build with `mobile/tool/build_internal_release.ps1`. The script invokes
`:app:verifyInternalReleaseConfiguration` before producing the signed APK.

## Future store release

The release owner must separately choose the store package, signing identity,
custody, backup, and Play App Signing policy. The internal key must not be
silently promoted into that role. Until that decision is made,
`:app:verifyProductionSigningConfiguration` fails by design.

Losing the internal identity prevents in-place updates of installed internal
APKs, so its keystore and encrypted credentials must be backed up securely.
