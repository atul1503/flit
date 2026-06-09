## Haptic feedback. A short tactile pulse on devices with haptic
## hardware (iPhone Taptic Engine, Android vibrator, macOS Force
## Touch trackpad).
##
## On hardware without haptics (most desktops without Force Touch),
## these procs are no-ops. SDL2 has an audio "beep" you could
## fall back to, but a silent no-op matches what users expect.
##
## Real implementations need per-platform native bindings:
## - iOS: `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`
## - Android: `Vibrator.vibrate(VibrationEffect)`
## - macOS: `NSHapticFeedbackManager.defaultPerformer.performFeedbackPattern`
## - Windows: no haptic API (controllers have rumble but not the
##   keyboard / trackpad)

type
  HapticKind* = enum
    ## Standard feedback patterns. Maps to platform equivalents.
    hkLight, hkMedium, hkHeavy, hkSuccess, hkWarning, hkError, hkSelection

proc hapticFeedback*(kind: HapticKind = hkLight) =
  ## Triggers a haptic pulse on supported hardware. No-op
  ## elsewhere. Safe to call from any widget handler.
  when defined(macosx):
    # NSHapticFeedbackManager exists but needs Objective-C binding.
    # Today this is a stub. Real implementation would call
    # NSHapticFeedbackManager.defaultPerformer.performFeedbackPattern.
    discard
  elif defined(ios):
    # UIImpactFeedbackGenerator binding needed.
    discard
  elif defined(android):
    # JNI call to Vibrator.vibrate needed.
    discard
  else:
    discard
