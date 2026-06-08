## Desktop runner: SDL2 window, event loop, frame pump. Used on macOS,
## Linux, and Windows.

when defined(js):
  {.error: "desktop runner is not available on the JS backend".}

import sdl2
import std/[times, os]
import ../../foundation/[widget, render_object, binding, geometry,
                          runtime, diagnostics]
import ../../rendering/canvas_sdl

type
  DesktopWindowConfig* = object
    title*: string
    width*, height*: int
    resizable*: bool
    highDpi*: bool
    vsync*: bool
    fontPath*: string

proc defaultDesktopConfig*(): DesktopWindowConfig =
  DesktopWindowConfig(title: "flit", width: 1024, height: 768,
                      resizable: true, highDpi: true, vsync: true,
                      fontPath: "")

proc runDesktop*(rootWidget: Widget,
                 config: DesktopWindowConfig = defaultDesktopConfig()) =
  if sdl2.init(INIT_VIDEO or INIT_EVENTS) != SdlSuccess:
    echo "SDL_Init failed: ", getError()
    return

  var flags: uint32 = SDL_WINDOW_SHOWN
  if config.resizable: flags = flags or SDL_WINDOW_RESIZABLE
  if config.highDpi:   flags = flags or SDL_WINDOW_ALLOW_HIGHDPI

  let window = createWindow(config.title, SDL_WINDOWPOS_CENTERED,
                            SDL_WINDOWPOS_CENTERED,
                            cint(config.width), cint(config.height), flags)
  if window.isNil:
    echo "createWindow failed: ", getError()
    return

  var rflags: cint = Renderer_Accelerated
  if config.vsync: rflags = rflags or Renderer_PresentVsync
  let renderer = createRenderer(window, -1, rflags)
  if renderer.isNil:
    echo "createRenderer failed: ", getError()
    return

  # Auto-discover a system font if the caller didn't pass one. Without a
  # font the SDL canvas silently skips every drawText call, which makes
  # every label and button look empty even when layout is correct.
  var fontPath = config.fontPath
  if fontPath.len == 0:
    const candidates = [
      "/System/Library/Fonts/Supplemental/Arial.ttf",
      "/System/Library/Fonts/Supplemental/Helvetica.ttc",
      "/Library/Fonts/Arial.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
      "/usr/share/fonts/TTF/DejaVuSans.ttf",
      "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
      "C:/Windows/Fonts/arial.ttf",
    ]
    for c in candidates:
      if fileExists(c):
        fontPath = c
        break
    if fontPath.len > 0:
      flogi("flit using font: ", fontPath)
    else:
      flogw("flit found no system font; text will not render")
  let canvas = newSdlCanvas(window, renderer,
                            config.width, config.height,
                            fontPath)
  let binding = newBinding(canvas,
                           Size(width: float32(config.width),
                                height: float32(config.height)))

  # Mount the widget tree
  let rootElement = mountElement(nil, rootWidget, 0)
  binding.rootElement = rootElement

  # Lay out and paint initial frame
  let rootConstraints = tightFor(binding.surfaceSize)
  runLayout(rootElement, rootConstraints)
  canvas.clear(0xFFFFFFFF'u32)
  runPaint(rootElement, canvas)
  canvas.present()

  flogi("flit desktop runner started ", config.width, "x", config.height)

  var ev: sdl2.Event
  var running = true
  while running:
    while sdl2.pollEvent(ev):
      case ev.kind
      of QuitEvent:
        running = false
      of WindowEvent:
        let we = cast[WindowEventPtr](addr ev)
        if we.event == WindowEvent_Resized or we.event == WindowEvent_SizeChanged:
          let nw = we.data1
          let nh = we.data2
          canvas.resize(int(nw), int(nh))
          binding.surfaceSize = Size(width: float32(nw), height: float32(nh))
          binding.dirtyRoots.add(rootElement)
      of MouseMotion:
        let me = cast[MouseMotionEventPtr](addr ev)
        binding.dispatchPointer(PointerEvent(
          kind: peMove, pointer: 0,
          position: Offset(dx: float32(me.x), dy: float32(me.y)),
          delta: Offset(dx: float32(me.xrel), dy: float32(me.yrel)),
          timestamp: binding.currentTime))
      of MouseButtonDown:
        let mb = cast[MouseButtonEventPtr](addr ev)
        binding.dispatchPointer(PointerEvent(
          kind: peDown, pointer: int(mb.which),
          position: Offset(dx: float32(mb.x), dy: float32(mb.y)),
          buttons: uint32(mb.button),
          timestamp: binding.currentTime))
      of MouseButtonUp:
        let mb = cast[MouseButtonEventPtr](addr ev)
        binding.dispatchPointer(PointerEvent(
          kind: peUp, pointer: int(mb.which),
          position: Offset(dx: float32(mb.x), dy: float32(mb.y)),
          buttons: uint32(mb.button),
          timestamp: binding.currentTime))
      of MouseWheel:
        let mw = cast[MouseWheelEventPtr](addr ev)
        # Get current mouse position so scroll lands on the right viewport
        var mx, my: cint
        discard getMouseState(mx, my)
        binding.dispatchPointer(PointerEvent(
          kind: peScroll, pointer: 0,
          position: Offset(dx: float32(mx), dy: float32(my)),
          scrollDelta: Offset(dx: float32(mw.x), dy: float32(mw.y)),
          timestamp: binding.currentTime))
      of KeyDown:
        let ke = cast[KeyboardEventPtr](addr ev)
        binding.dispatchKey(KeyEvent(
          kind: keDown, keyCode: int(ke.keysym.sym),
          scancode: int(ke.keysym.scancode),
          modifiers: uint32(ke.keysym.modstate)))
      of KeyUp:
        let ke = cast[KeyboardEventPtr](addr ev)
        binding.dispatchKey(KeyEvent(
          kind: keUp, keyCode: int(ke.keysym.sym),
          scancode: int(ke.keysym.scancode),
          modifiers: uint32(ke.keysym.modstate)))
      else: discard

    # Drain pointer events into gesture detectors. May enqueue dirty roots
    # via setState callbacks.
    processPointerEvents(binding)

    # Rebuild dirty subtrees
    if binding.dirtyRoots.len > 0:
      for r in binding.dirtyRoots:
        rebuildElement(r)
      binding.clearDirty()
      runLayout(rootElement, tightFor(binding.surfaceSize))
      canvas.clear(0xFFFFFFFF'u32)
      runPaint(rootElement, canvas)
      canvas.present()
    else:
      # Animation pump. Snapshot the callback list and clear FIRST, because
      # tickers re-schedule themselves by appending during the callback;
      # clearing after the loop would erase those re-schedules.
      if binding.frameCallbacks.len > 0:
        let now = binding.currentTime
        let pending = binding.frameCallbacks
        binding.frameCallbacks.setLen(0)
        for cb in pending:
          cb(now)
        # The callbacks may have set state, so check for dirty roots before
        # painting.
        if binding.dirtyRoots.len > 0:
          for r in binding.dirtyRoots: rebuildElement(r)
          binding.clearDirty()
          runLayout(rootElement, tightFor(binding.surfaceSize))
        canvas.clear(0xFFFFFFFF'u32)
        runPaint(rootElement, canvas)
        canvas.present()
      else:
        sleep(8)
    inc binding.frameCount

  destroy(renderer)
  destroy(window)
  sdl2.quit()
