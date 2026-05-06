# Android Build Notes (Staging)

Date: 2026-03-30

## Scope
This project uses Flutter `dart-define` strategy for staging configuration.
No dedicated Android flavor is required for staging baseline build.

## Required files
- Android runner shell under `mobile/android/`
- Staging defines:
  - `mobile/env/dart_define.staging.example.json`

## Build commands
1. `flutter clean`
2. `flutter pub get`
3. Release APK:
   - `flutter build apk --dart-define-from-file=env/dart_define.staging.example.json`

Optional debug APK:
- `flutter build apk --debug --dart-define-from-file=env/dart_define.staging.example.json`

## GitHub Actions build
- Workflow file:
  - `.github/workflows/android-apk-build.yml`
- Trigger:
  - manual (`workflow_dispatch`) or push affecting `mobile/**`
- Build command used in CI:
  - `flutter build apk --debug --dart-define-from-file=env/dart_define.staging.example.json`
- Artifact name:
  - `kundi-android-apk`

## Embedded staging config
From dart-define file:
- `API_BASE_URL`
- `ENABLE_DEBUG_SURFACES`

Current staging API base URL:
- `http://46.247.42.87:18080`

## Output locations
- Release APK:
  - `mobile/build/app/outputs/flutter-apk/app-release.apk`
- Debug APK:
  - `mobile/build/app/outputs/flutter-apk/app-debug.apk`

## Notes
- iOS is intentionally out of scope.
- Release signing is not configured in this step; release build uses debug signing config by default.
- Current local host may fail APK build under memory pressure; CI path is the recommended baseline.
