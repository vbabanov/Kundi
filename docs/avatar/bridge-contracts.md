# AvatarFacade Bridge Contracts (Verified)

## Commands
- `initializeAvatar`
- `showAvatar`
- `hideAvatar`
- `startListening`
- `startThinking`
- `speak(responsePackage)`
- `interrupt`
- `setEmotion`
- `playGesture`
- `resetToIdle`

## Events
- `avatarReady`
- `playbackStarted`
- `playbackCompleted`
- `interrupted`
- `error`

## Boundary rule
- Flutter feature/UI code communicates only via `AvatarFacade` + bridge interfaces.
- No direct Unity internals are exposed to feature pages.

## Known limitations
- Event payload taxonomy is still baseline (needs richer codes for production telemetry).
- Native host forwarding implementation is still a bridge TODO in Unity comments.

