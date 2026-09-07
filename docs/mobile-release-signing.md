# Android release signing gate

Kundi release builds must never use Android's debug signing identity. Without an approved production identity, CI produces an explicitly unsigned AAB for compile verification only. That artifact must not be distributed to users or uploaded to an app store.

## External approval required

The release owner must create or nominate the permanent Android application signing identity, approve its custody and backup locations, and record the certificate SHA-256 fingerprint outside source control. Automation must receive all four values from a protected secret store:

- `KUNDI_ANDROID_KEYSTORE_PATH`
- `KUNDI_ANDROID_KEYSTORE_PASSWORD`
- `KUNDI_ANDROID_KEY_ALIAS`
- `KUNDI_ANDROID_KEY_PASSWORD`

Do not commit a keystore, passwords, a populated properties file, or command output containing these values. Partial configuration fails during Gradle configuration. A configured keystore path must resolve to a readable file.

## Release procedure

1. Inject the four values only into the isolated release job.
2. Run `./android/gradlew -p android :app:verifyProductionSigningConfiguration`.
3. Build the release AAB with production crash reporting configuration and a stable `KUNDI_RELEASE` identifier.
4. Verify the AAB certificate against the separately approved SHA-256 fingerprint.
5. Archive the signed AAB, checksums, source SHA, toolchain versions, and certificate fingerprint together.
6. Remove the temporary keystore file and signing environment from the runner.

Losing the permanent signing identity can make future updates impossible. Rotation, Play App Signing enrollment, and recovery custody therefore require an explicit owner decision; this repository does not generate or rotate that identity automatically.
