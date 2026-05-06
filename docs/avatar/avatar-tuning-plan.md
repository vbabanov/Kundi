# Avatar Tuning Plan

## Objective
Separate technical integration from behavioral/artistic tuning.

## Tuning layers
1. Backend policy level
   - tutor vs general mode routing
   - grade-band persona policy
   - pedagogy flags
   - audio_status fallback policy
2. Avatar runtime level (Unity/native)
   - animation state machine transitions
   - interruption safety
   - lip sync driver stability
   - error event handling
3. Content/animation level
   - gesture appropriateness by lesson context
   - emotion transition smoothness
   - timing calibration for speech pace

## QA checklist
1. Tone by grade band
   - primary/middle/senior feel distinct
2. Animation timing
   - no early cutoffs or stuck states
3. Gesture appropriateness
   - no over-animated behavior for simple answers
4. Emotion transitions
   - smooth blend, no abrupt jumps
5. Lip sync quality
   - viseme timing aligns with audio playback
6. TTS unavailable fallback
   - neutral non-speaking fallback, no fake mouth movement
