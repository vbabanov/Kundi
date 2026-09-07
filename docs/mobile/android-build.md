# Android Build Guide (Staging)

Date: 2026-03-30

## Scope
- Android only, using the `internal` private-distribution flavor.
- No backend/iOS changes.
- Staging configuration via `dart-define`.

## Required staging define file
- `mobile/env/dart_define.staging.example.json`

Expected keys:
1. `API_BASE_URL`
2. `ENABLE_DEBUG_SURFACES`

Current staging API base URL:
- `http://46.247.42.87:18080`

## Local build steps
From repo root:
1. `cd mobile`
2. `flutter clean`
3. `flutter pub get`
4. Debug APK:
   - `flutter build apk --flavor internal --debug --dart-define-from-file=env/dart_define.staging.example.json`
5. Optional release APK:
   - `flutter build apk --flavor internal --dart-define-from-file=env/dart_define.staging.example.json`

Expected outputs:
- `mobile/build/app/outputs/flutter-apk/app-internal-debug.apk`
- `mobile/build/app/outputs/flutter-apk/app-internal-release.apk`

## GitHub Actions build steps
- Workflow: `.github/workflows/android-apk-build.yml`
- Job sequence:
1. Checkout repository
2. Setup Java 17 (Temurin)
3. Setup Flutter 3.41.4
4. `flutter pub get`
5. `flutter build apk --flavor internal --debug --dart-define-from-file=env/dart_define.staging.example.json`
6. Upload artifact `kundi-android-apk`

## Operational note
- Runner recovery is complete.
- If local machine is memory-constrained, use GitHub Actions artifact as baseline APK source.
