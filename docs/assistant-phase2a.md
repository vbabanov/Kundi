# Kundi Assistant Phase 2A: system voice input

Phase 2A adds push-to-talk input to the existing text Assistant. It uses the
Android system `SpeechRecognizer`; it does not add speech playback, Azure
Speech, TTS, visemes, lip-sync, or a second assistant conversation.

## Privacy and persistence

- The app does not record, upload, or store microphone audio.
- Android performs speech recognition through the system recognition service.
- A non-empty final transcript is sent once through the existing Assistant
  message API and is stored in the shared conversation history as
  `input_mode=voice`.
- Partial transcripts stay in memory for the listening UI and are not sent or
  persisted.
- Default-off QA telemetry contains only opaque correlation IDs, counters,
  lifecycle states, locale mappings, and text length. It must not contain
  transcript text, tokens, headers, secrets, or student identity.

## Permission and lifecycle UX

The microphone permission is requested only after an enabled voice hold. A
denial or permanent denial ends the current gesture transaction and leaves the
next independent tap available for opening the text Assistant. Backgrounding,
cancellation, disposal, late callbacks, and duplicate terminal results are
generation-guarded. Granting permission never starts recognition implicitly;
the learner begins a new hold.

## Locale mapping

- Assistant session `ru`, `ru-KZ`, or `ru-RU` maps to recognizer `ru-RU`.
- Assistant session `kk` or `kk-KZ` maps to recognizer `kk-KZ`.
- Unknown or not-yet-loaded session locale falls back to `ru-RU`.

The intended session must be loaded before a hold. Recognition quality and
Kazakh availability depend on the system recognition service installed on the
device; a technically available recognizer can still return no usable result.

## Feature and packaging gates

The Flutter flags default to `false`:

- `ENABLE_KUNDI_ASSISTANT`
- `ENABLE_KUNDI_VOICE_INPUT`
- `ENABLE_KUNDI_VOICE_QA_TELEMETRY`

Android voice packaging is controlled by the Gradle/environment property
`ENABLE_KUNDI_VOICE_INPUT`. Voice-enabled builds must pass the value through
both the Gradle environment and Flutter `--dart-define` channels. Voice-off
release builds do not register the native speech host and do not declare
`RECORD_AUDIO` or query `android.speech.RecognitionService`.

Realtime avatar packaging remains independently controlled by
`ENABLE_KUNDI_HOME_REALTIME_AVATAR`. An avatar-off build excludes Filament and
the GLB; an avatar-on build contains the single balanced
`kundi_home_mobile.glb` asset.

## History policy

`assistantControllerProvider` is retained in the root `ProviderScope`. Its
first build requests the session list once and the active session messages
once. Route rebuilds, closing and reopening Assistant, and opening the history
sheet reuse that state and do not issue another message-history request. The
two requests observed during device QA were `listSessions` and `listMessages`,
not duplicate history GETs.

## Validation

The permission lifecycle, locale mapping, and exactly-once message flow were
validated on:

- Redmi Note 7, Android 10;
- Xiaomi 22101316UG, Android 14.

The rollout flags remain disabled by default. Production enablement requires a
separate rollout approval. Phase 2A does not deploy services or apply database
migrations by itself.
