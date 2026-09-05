# Kundi Assistant Phase 2B: Azure speech playback

Phase 2B adds opt-in speech playback for checked Assistant responses and
coordinates playback with the Kundi avatar. The feature remains disabled by
default and does not change the existing text-only Assistant flow.

## Feature gates and Android variants

The backend gate `KUNDI_TTS_ENABLED`, Flutter gate `ENABLE_KUNDI_TTS`, and
Android Gradle/environment gate `ENABLE_KUNDI_TTS` all default to `false`.
Automatic playback also requires the existing Assistant and voice-input gates.

The TTS-off Android source set provides a no-op host and does not include the
Azure SDK or register the TTS platform channel. Its minimum Android API remains
24. The TTS-on source set uses
`com.microsoft.cognitiveservices.speech:client-sdk:1.51.1` and requires API 26
because the SDK's dependencies use Android O APIs. Unused keyword-spotting and
SILK native extensions are excluded from packaging.

## Authorization and data boundaries

The authenticated endpoint
`POST /v1/assistant/sessions/{sessionID}/messages/{messageID}/speech-authorization`
returns `Cache-Control: no-store`. Before issuing a short-lived Azure token, the
backend verifies all of the following:

- the session belongs to the authenticated student;
- the message belongs to that session and student;
- the message is an Assistant response paired through `client_message_id` with
  a voice-originated user message;
- neither record is deleted and the checked response is non-empty and within
  the configured limit.

The primary Azure resource key is attempted first. Only HTTP 401 or 403 allows
one secondary-key attempt. The complete broker operation has a five-second
timeout, does not follow redirects, and accepts only approved HTTPS Azure
origins. Per-process bounds cover request rate, concurrent issuance, cached
messages, and attempts per message.

Azure resource keys remain on the backend. Tokens, 24 kHz signed 16-bit mono
PCM, viseme events, and word-boundary timelines remain in memory. Completion,
cancellation, lifecycle shutdown, and disposal wipe or release the buffers.
The app does not persist tokens or audio and does not write WAV, PCM, MP3, audio
URLs, synthesis timelines, or raw Azure responses to history or logs.

## Voices, playback, and lip sync

Russian uses `ru-RU-SvetlanaNeural`. Kazakh uses
`kk-KZ-AigulNeural`. The Android runtime validates the authorization hash,
locale, voice, PCM format, event bounds, duration, and package size before
playback.

Russian normally uses Azure viseme offsets. Current Kazakh synthesis can return
only neutral Azure visemes, so Kazakh uses WordBoundary timing with a
deterministic vowel-to-mouth mapping. PCM amplitude is the final fallback when
word timing is unavailable.

`AudioTrack` owns one bounded streaming buffer and follows the playback head.
The Flutter coordinator holds Waiting during authorization and synthesis, then
starts body and mouth animation only after native playback begins. Home speech
uses the frontal `Talking2` clip exclusively. `Talking` and `Talking3` remain in
the GLB for future experiences but are excluded from the Home speaking path.
Completion and cancellation reset the face and return the avatar to neutral,
frozen `Standing`.

## Autoplay, locale, history, and lifecycle

Only a newly completed, voice-originated response with `replayed=false` may
request speech authorization and playback. Typed sends, history reads, route
reopen, refresh, application restart, and idempotent replay do not start TTS.
Missing replay metadata fails closed.

Before the first voice hold starts the microphone, the locale resolver uses an
active Assistant session or waits for the existing Assistant initialization to
ensure one. The existing in-flight initialization is shared, and gesture
generation guards prevent an old asynchronous resolution from starting a newer
recognizer turn. `ru-KZ` is used only as the documented failure fallback. Native
mapping remains `ru-KZ` to `ru-RU` and `kk-KZ` to `kk-KZ`.

Assistant history uses stale-while-revalidate. Initial loading may show a full
loading or retry state. Once data exists, refresh errors retain sessions, the
active session, and messages and show a non-blocking retry banner. A successful
retry clears the transient error without creating a new session.

A new hold cancels active playback before the system recognizer starts.
Activity pause, screen off, audio-focus loss, channel detach, and disposal also
cancel playback, release `AudioTrack` and audio focus, clear pending timelines,
and invalidate the active generation. Late authorization, synthesis, and audio
callbacks cannot restart sound or Talking.

## Reproducible verification

Run backend tests from `backend`:

```text
go test ./...
```

PostgreSQL integration tests use an explicitly supplied disposable
`TEST_DATABASE_URL`. Never point them at a production database.

Run Flutter tests and analysis from `mobile`:

```text
flutter test --concurrency=1
flutter analyze
```

Run Android JVM tests from `mobile/android` with TTS and the realtime avatar
enabled for the test variant:

```text
gradlew.bat :app:testDebugUnitTest -PENABLE_KUNDI_TTS=true -PENABLE_KUNDI_HOME_REALTIME_AVATAR=true -PENABLE_KUNDI_VOICE_INPUT=true
```

`mobile/tool/build_tts_matrix.ps1` builds four release arm64 combinations and
checks Azure libraries and channel registration, Filament, one balanced GLB,
ABI contents, and absence of Unity. `mobile/tool/audit_tts_secrets.ps1` accepts
an explicit local secret-file path and compares the real resource keys against
all APK entries without printing or persisting their values. Build outputs and
audit reports remain ignored local artifacts.

## Rollout status

The implementation, automated checks, two-device playback/lifecycle checks,
history behavior, barge-in, and bounded replay stress have passed feature-branch
validation. Production canary remains blocked until a representative Alem
latency sample is collected under canary conditions. Two observed Kazakh Alem
requests reached the provider timeout; controlled downstream Kazakh playback
passed. Final visual eye-contact confirmation for `Talking2`, production secret
provisioning, migration operations, deployment, and observability limits remain
separate rollout gates.
