# Audio Status Verification

## Contract
- `audio_status=ready`
  - `audioUrl` must be present
  - viseme track can be used
  - emotion/gesture playback package is expected
- `audio_status=unavailable`
  - `audioUrl` should be empty
  - no fake viseme package should be sent
  - fallback neutral behavior should be used

## Verification matrix
1. Audio available path
   - backend returns `ready`
   - mobile repository maps status correctly
   - avatar runtime receives speak package with audio
2. Audio unavailable path
   - backend returns `unavailable`
   - mobile repository maps status correctly
   - avatar fallback behavior is triggered
3. Interrupted playback
   - audio status remains tied to message contract
   - interruption event sequence remains valid
