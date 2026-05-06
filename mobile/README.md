# Mobile

Flutter feature-first architecture.

Key runtime decisions:
- Riverpod state management
- SQLite canonical cache
- secure storage for diary credentials and session secrets
- connector runtime isolated under `runtimes/connector_runtime`
- avatar runtime exposed via `AvatarFacade`

## Environment strategy
- API endpoint is provided by dart define:
  - `API_BASE_URL`
- Debug surfaces are controlled by:
  - `ENABLE_DEBUG_SURFACES`

Example launch commands:
- `flutter run --dart-define-from-file=env/dart_define.dev.example.json`
- `flutter run --dart-define-from-file=env/dart_define.staging.example.json`
- `flutter run --dart-define-from-file=env/dart_define.prod.example.json --dart-define=USE_TYPED_V2_READ=true --dart-define=ENABLE_V2_PARITY_SHADOW=true`

## Android build
- Staging APK (release):
  - `flutter build apk --dart-define-from-file=env/dart_define.staging.example.json`
- Staging APK (debug):
  - `flutter build apk --debug --dart-define-from-file=env/dart_define.staging.example.json`
- Prod API hookup APK (debug):
  - `flutter build apk --debug --dart-define-from-file=env/dart_define.prod.example.json --dart-define=USE_TYPED_V2_READ=true --dart-define=ENABLE_V2_PARITY_SHADOW=true`

See detailed Android shell/build notes in:
- `mobile/ANDROID_BUILD_NOTES.md`
- `docs/mobile/android-build.md`

CI build:
- `.github/workflows/android-apk-build.yml`
