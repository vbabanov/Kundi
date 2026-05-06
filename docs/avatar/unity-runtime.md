# Unity Avatar Runtime Design

## Runtime model
- Animator state machine as authoritative motion graph.
- Viseme blend shape driver for lip sync.
- Additive emotion layer.
- Gesture layer over base motions.
- Idle micro-motion loop.
- Interruption-safe transitions.
- Addressables-ready content loading.

## Command surface
- `initializeAvatar()`
- `showAvatar()`
- `hideAvatar()`
- `startListening()`
- `startThinking()`
- `speak(responsePackage)`
- `interrupt()`
- `setEmotion()`
- `playGesture()`
- `resetToIdle()`

## Event surface
- `avatarReady`
- `playbackStarted`
- `playbackCompleted`
- `interrupted`
- `error`
