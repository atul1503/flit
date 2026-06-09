## Window decoration overrides: borderless windows, transparent
## backgrounds, vibrancy / acrylic / blur effects.
##
## SDL2 supports borderless, transparent, and fullscreen-without-
## decoration via window flags. Native effects (vibrancy on macOS,
## acrylic on Windows, blur on Linux) need per-platform native
## binding (NSVisualEffectView, DwmExtendFrameIntoClientArea,
## window manager hints). This module exposes the cross-platform
## subset via SDL and stubs the native-only effects.

when defined(js):
  {.error: "window decorations are not available on the JS backend".}

import sdl2

type
  WindowEffect* = enum
    ## Native window-background effect to apply. Maps to per-OS
    ## APIs: `weVibrancyLight` / `weVibrancyDark` use macOS's
    ## NSVisualEffectView; `weAcrylic` uses Windows DWM acrylic;
    ## `weBlur` uses the Linux compositor's blur hint. `weNone`
    ## removes any active effect.
    weNone, weVibrancyLight, weVibrancyDark, weAcrylic, weBlur

proc setWindowBorderless*(window: WindowPtr, borderless: bool) =
  ## Removes the title bar and edges. Useful for splash screens,
  ## kiosks, custom title-bar designs.
  setBordered(window, if borderless: False32 else: True32)

proc setAlwaysOnTop*(window: WindowPtr, onTop: bool) =
  ## Pins the window above all others. The SDL2 binding in flit's
  ## current version doesn't expose this directly; future SDL2
  ## binding upgrades enable it. Stubbed for now.
  discard

proc setOpacity*(window: WindowPtr, opacity: float32) =
  ## Sets the whole-window opacity (0.0 transparent to 1.0
  ## opaque). Compositor-supported. Same SDL2 binding caveat
  ## as `setAlwaysOnTop`. Stubbed.
  discard

proc setWindowEffect*(window: WindowPtr, effect: WindowEffect) =
  ## Applies a native window-background effect. Currently a stub
  ## that logs intent; real implementation requires per-platform
  ## native binding work.
  ##
  ## Once implemented, macOS uses NSVisualEffectView, Windows
  ## uses DWM acrylic, GNOME/KDE use their compositor extensions.
  if effect == weNone: return
  echo "[flit/window] setWindowEffect: ", effect,
       " (stub; native effect binding is a follow-up)"
