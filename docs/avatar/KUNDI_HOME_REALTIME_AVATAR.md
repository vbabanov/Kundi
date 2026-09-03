# Kundi Home realtime avatar

## Scope and rollout

The Home avatar can render the balanced Kundi GLB through an Android Filament
renderer backed by Flutter `SurfaceProducer` and exposed as a `Texture`. The
rollout is disabled by default.
The retained WebP remains the loading, error, and unsupported-device fallback.
No backend, Assistant Safety, or Unity runtime dependency is required for this
path.

Enable the production path only with all required build defines:

```text
USE_TYPED_V2_READ=true
ENABLE_V2_PARITY_SHADOW=true
ENABLE_KUNDI_BEHAVIOR_CORE=true
ENABLE_KUNDI_HOME_REALTIME_AVATAR=true
```

The default for `ENABLE_KUNDI_HOME_REALTIME_AVATAR` remains `false`. When the
flag is enabled, Flutter Texture is the only production composition path.

## Composition and lifecycle

1. Flutter keeps the retained loading WebP opaque while it mounts the Texture,
   loads the model, and requests native presentation priming.
2. Native priming requires 18 successful submissions, at least 700 ms, and has
   a 1500 ms timeout.
3. Flutter waits for the typed priming event and one end-of-frame barrier, then
   fades the retained layer. The live Texture becomes the primary layer only
   after that fade completes.
4. Home greeting runs on the live GLB. Its completion applies and renders the
   `Standing` rest pose before cadence freezes at zero FPS.
5. Home → ДЗ → Home retains the renderer/model session during its grace period;
   it restores the final live `Standing` frame without replaying the greeting.

Fatal renderer errors cancel priming, suppress late lifecycle completion, stop
frame callbacks, and keep the static fallback visible.

## Animation contract

| Product state | GLB animation |
|---|---|
| default/rest/neutral | `Standing` |
| listening | `Idle` |
| thinking, warning, error | `Waiting` |
| speaking or Home greeting | `Talking`, `Talking2`, or `Talking3` |
| celebration | `Dansing` |

`Idle` is not the default rest pose. The live renderer applies neutral face,
open eyes, neutral mouth, and `Standing` before a frozen rest state.

## Eligibility and Redmi Note 7 validation

Realtime rendering requires Android API 29+, `arm64-v8a`, OpenGL ES 3.0+, a
non-low-RAM device, and successful Filament initialization. Devices that do not
meet these checks remain on the WebP fallback.

The Redmi Note 7 (Android 10) smoke validation established:

- native priming reached 18 submissions in 795 ms;
- no blank handoff frame or static waving fallback;
- live greeting returned to frozen live `Standing`;
- quick Home return retained `rendererCreateCount=1`, `modelLoadCount=1`, and
  `fullDisposeCount=0`;
- no renderer error, crash, or ANR in the smoke sequence.

The retained loading Standing pose and the first fully live Standing pose are
slightly different. Asset, camera, lighting, placement, and Home layout are
currently held constant to keep rollout risk bounded.

## Known limits

- This is Android/Filament Texture scope; unsupported platforms use the WebP.
- Validation evidence is device-specific, not a substitute for a full device
  matrix, accessibility review, or text-scale review.
- The renderer grace period is intended for fast navigation return, not for
  indefinite background retention.
