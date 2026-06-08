## Mobile runner. Uses SDL2 on iOS and Android (SDL2 ships both targets).
## The CLI (`flit build apk` / `flit build ipa`) wraps this in the right
## native shell. Touch input is mapped to PointerEvents the same way as
## desktop mouse input.

when defined(android) or defined(ios):
  import sdl2
  import std/[times]
  import ../../foundation/[widget, binding, geometry, runtime]
  import ../../rendering/canvas_sdl

  proc runMobile*(rootWidget: Widget,
                  title = "flit-app", fontPath = "") =
    if sdl2.init(INIT_VIDEO or INIT_EVENTS) != SdlSuccess:
      return
    # On mobile, SDL window dimensions equal device screen; we open full.
    var dm: DisplayMode
    discard getCurrentDisplayMode(0, dm)
    let window = createWindow(title, 0, 0, dm.w, dm.h,
                              SDL_WINDOW_FULLSCREEN or SDL_WINDOW_ALLOW_HIGHDPI)
    let renderer = createRenderer(window, -1,
                                  SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC)
    let canvas = newSdlCanvas(window, renderer, dm.w, dm.h, fontPath)
    let binding = newBinding(canvas,
                             Size(width: float32(dm.w), height: float32(dm.h)),
                             devicePixelRatio = 2.0)
    let rootElement = mountElement(nil, rootWidget, 0)
    binding.rootElement = rootElement
    runLayout(rootElement, tightFor(binding.surfaceSize))
    canvas.clear(0xFFFFFFFF'u32)
    runPaint(rootElement, canvas)
    canvas.present()

    var ev: sdl2.Event
    var running = true
    while running:
      while sdl2.pollEvent(ev):
        case ev.kind
        of QuitEvent: running = false
        of FingerDown, FingerUp, FingerMotion:
          let te = cast[TouchFingerEventPtr](addr ev)
          let p = Offset(dx: float32(te.x) * binding.surfaceSize.width,
                         dy: float32(te.y) * binding.surfaceSize.height)
          let kind = case ev.kind
            of FingerDown:   peDown
            of FingerUp:     peUp
            else:            peMove
          binding.dispatchPointer(PointerEvent(
            kind: kind, pointer: int(te.fingerId), position: p,
            timestamp: binding.currentTime))
        else: discard

      if binding.dirtyRoots.len > 0:
        for r in binding.dirtyRoots: rebuildElement(r)
        binding.clearDirty()
        runLayout(rootElement, tightFor(binding.surfaceSize))
      canvas.clear(0xFFFFFFFF'u32)
      runPaint(rootElement, canvas)
      canvas.present()
else:
  # Stubs for non-mobile builds so users can `import flit/platform/mobile/runner`
  # without conditional compilation noise.
  import ../../foundation/widget
  proc runMobile*(rootWidget: Widget, title = "flit-app", fontPath = "") =
    raise newException(Defect, "runMobile is only available on android/ios builds")
