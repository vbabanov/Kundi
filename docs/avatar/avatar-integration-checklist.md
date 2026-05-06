# Avatar Integration Checklist

## Scope
Validate the technical path:
`AvatarFacade -> native bridge -> Unity runtime`.

## Command flow checks
1. `initializeAvatar()`
   - emits `avatarReady`
2. `showAvatar()` / `hideAvatar()`
   - visibility changes correctly
3. `startListening()` / `startThinking()`
   - animation state transition is correct
4. `speak(responsePackage)`
   - playback starts and completes
   - interruption-safe behavior
5. `interrupt()`
   - emits `interrupted`
6. `resetToIdle()`
   - returns to idle micro-motion

## Event checks
1. `avatarReady`
2. `playbackStarted`
3. `playbackCompleted`
4. `interrupted`
5. `error`

## Failure-path checks
- missing audio URL with `audio_status=unavailable`
- bridge method failures emit typed error event
- playback cancellation does not leave runtime in broken state
