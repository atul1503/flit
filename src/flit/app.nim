## App entry. The user calls `runApp(myRootWidget)` and `flit` picks
## the right platform backend at compile time based on which target
## (and which `-d:flag`) the program was built for.
##
## How the platform is chosen:
##
## ```
## nim c     examples/counter/main.nim           # desktop (SDL2)
## nim c -d:android examples/counter/main.nim    # android (SDL2 mobile)
## nim c -d:ios     examples/counter/main.nim    # iOS    (SDL2 mobile)
## nim js  examples/counter/web.nim              # web (HTMLCanvas)
## nim c -d:flitEmbedded examples/embed.nim      # framebuffer / kiosk
## ```
##
## The exported `runApp` proc's signature varies slightly per backend:
## the desktop runner takes a `DesktopWindowConfig`, the web runner
## takes a canvas element id, the mobile runner takes a title/font path,
## and the embedded runner takes width/height and a pixel-flush callback.

import ./foundation/widget

when defined(js):
  import ./platform/web/runner
  proc runApp*(w: Widget, canvasId = "flit-canvas") =
    ## Web entry point. Mounts `w` and starts the
    ## `requestAnimationFrame` loop against the `<canvas>` element
    ## identified by `canvasId` (defaults to `"flit-canvas"`).
    runWeb(w, canvasId)
elif defined(android) or defined(ios):
  import ./platform/mobile/runner
  proc runApp*(w: Widget, title = "flit-app", fontPath = "") =
    ## Mobile entry point. Opens an SDL2 fullscreen window, mounts
    ## `w`, and pumps frames. `title` is shown by the platform's
    ## app switcher. `fontPath` is an absolute path to a TTF; when
    ## empty, text drawing will be silent.
    runMobile(w, title, fontPath)
elif defined(flitEmbedded):
  import ./platform/embedded/runner
  proc runApp*(w: Widget, width = 800, height = 480,
               flush: EmbeddedFlush = nil, frameRateHz = 30) =
    ## Embedded / framebuffer entry point.
    ##
    ## Inputs:
    ## - `w`: root widget.
    ## - `width`, `height`: framebuffer dimensions in pixels.
    ## - `flush`: callback called once per frame with the ARGB pixel
    ##   buffer (`ptr UncheckedArray[uint32]`, `width`, `height`).
    ##   The host program writes those bytes to /dev/fb0 or whatever
    ##   output it owns. Required.
    ## - `frameRateHz`: target frame rate. Default 30.
    ##
    ## Raises `ValueError` if `flush` is nil.
    if flush.isNil:
      raise newException(ValueError, "embedded runApp requires a flush callback")
    runEmbedded(w, width, height, flush, frameRateHz)
else:
  import ./platform/desktop/runner
  export runner
  proc runApp*(w: Widget, config = defaultDesktopConfig()) =
    ## Desktop entry point (macOS / Linux / Windows).
    ##
    ## Inputs:
    ## - `w`: root widget. Required.
    ## - `config`: a `DesktopWindowConfig` controlling window size,
    ##   title, vsync, high-DPI, and font path. Defaults to a 1024x768
    ##   resizable vsync'd window with auto-discovered system font.
    ##
    ## Effect: blocks until the user closes the window. Drives the
    ## SDL2 event loop, runs frames, and dispatches input to gesture
    ## detectors.
    runDesktop(w, config)
