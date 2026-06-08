## App entry. `runApp(widget)` chooses the right backend at compile time
## based on `-d:flitPlatform=...` or the target OS:
##
##   nim c -d:release examples/counter/main.nim          # desktop (SDL2)
##   nim c -d:android examples/counter/mobile.nim        # android
##   nim c -d:ios     examples/counter/mobile.nim        # ios
##   nim js  -d:release examples/counter/web.nim         # web
##   nim c -d:flitPlatform=embedded examples/embed.nim   # embedded fb

import ./foundation/widget

when defined(js):
  import ./platform/web/runner
  proc runApp*(w: Widget, canvasId = "flit-canvas") =
    runWeb(w, canvasId)
elif defined(android) or defined(ios):
  import ./platform/mobile/runner
  proc runApp*(w: Widget, title = "flit-app", fontPath = "") =
    runMobile(w, title, fontPath)
elif defined(flitEmbedded):
  import ./platform/embedded/runner
  proc runApp*(w: Widget, width = 800, height = 480,
               flush: EmbeddedFlush = nil, frameRateHz = 30) =
    if flush.isNil:
      raise newException(ValueError, "embedded runApp requires a flush callback")
    runEmbedded(w, width, height, flush, frameRateHz)
else:
  import ./platform/desktop/runner
  export runner
  proc runApp*(w: Widget, config = defaultDesktopConfig()) =
    runDesktop(w, config)
