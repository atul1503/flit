## Desktop runner: SDL2 window, event loop, frame pump. Used on macOS,
## Linux, and Windows.
##
## Users typically don't import this directly; `runApp(widget)` from
## `flit/app` dispatches here on desktop builds. The public surface
## is `DesktopWindowConfig`, `defaultDesktopConfig`, and `runDesktop`.

when defined(js):
  {.error: "desktop runner is not available on the JS backend".}

import sdl2
import std/[times, os]
import ../../foundation/[widget, render_object, binding, geometry,
                          runtime, diagnostics, focus]
import ../../rendering/canvas_sdl
import ../../widgets/text_field
import ../../widgets/drag_drop
import ../../widgets/network_image

type
  DesktopWindowConfig* = object
    ## Configuration for the desktop SDL2 window. Fields:
    ## - `title`: window title bar text.
    ## - `width`, `height`: initial size in logical pixels.
    ## - `resizable`: whether the user can drag the edges.
    ## - `highDpi`: whether to request a HiDPI backing store on
    ##   retina displays.
    ## - `vsync`: whether to wait for vertical sync (caps to display
    ##   refresh rate).
    ## - `fontPath`: absolute path to a TTF file. Empty string asks
    ##   the runner to auto-discover a system font (Arial /
    ##   Helvetica / DejaVu Sans).
    title*: string
    width*, height*: int
    resizable*: bool
    highDpi*: bool
    vsync*: bool
    fontPath*: string

proc defaultDesktopConfig*(): DesktopWindowConfig =
  ## Returns a `DesktopWindowConfig` with the defaults
  ## flit's examples use: 1024x768 resizable HiDPI vsync'd window
  ## titled "flit", auto-discovered system font.
  DesktopWindowConfig(title: "flit", width: 1024, height: 768,
                      resizable: true, highDpi: true, vsync: true,
                      fontPath: "")

proc runDesktop*(rootWidget: Widget,
                 config: DesktopWindowConfig = defaultDesktopConfig()) =
  ## Opens the SDL2 window described by `config`, mounts `rootWidget`,
  ## and pumps the event loop. Blocks until the user closes the window.
  ##
  ## Inputs:
  ## - `rootWidget`: the top of the widget tree.
  ## - `config`: window settings. Defaults to
  ##   `defaultDesktopConfig()`.
  ##
  ## Effect: drives layout, paint, frame callbacks, and pointer event
  ## dispatch each iteration. Returns when the user closes the
  ## window or `SDL_Quit` is received.
  if sdl2.init(INIT_VIDEO or INIT_EVENTS) != SdlSuccess:
    echo "SDL_Init failed: ", getError()
    return

  # Enable SDL text-input events so keyboard typing reaches the
  # focus manager. The TextInput event fires for printable
  # characters and IME composition output.
  startTextInput()

  # Install SDL-backed clipboard provider so TextField's
  # cut/copy/paste work without forcing TextField to import SDL.
  clipboardGet = proc(): string {.gcsafe.} =
    {.gcsafe.}:
      let p = sdl2.getClipboardText()
      result = if p.isNil: "" else: $p
  clipboardSet = proc(text: string) {.gcsafe.} =
    {.gcsafe.}:
      discard sdl2.setClipboardText(text.cstring)

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
        let kev = KeyEvent(
          kind: keDown, keyCode: int(ke.keysym.sym),
          scancode: int(ke.keysym.scancode),
          modifiers: uint32(ke.keysym.modstate))
        binding.dispatchKey(kev)
        # Route control keys (Tab, Backspace, arrows, Enter, etc.)
        # through the focus manager. Printable characters arrive
        # via the TextInput event instead.
        if focusManager().handleKeyEvent(kev):
          binding.needsRepaint = true
      of KeyUp:
        let ke = cast[KeyboardEventPtr](addr ev)
        binding.dispatchKey(KeyEvent(
          kind: keUp, keyCode: int(ke.keysym.sym),
          scancode: int(ke.keysym.scancode),
          modifiers: uint32(ke.keysym.modstate)))
      of TextEditing:
        let te = cast[TextEditingEventPtr](addr ev)
        var s = newString(0)
        for i in 0 ..< 32:
          let c = te.text[i]
          if c == '\0': break
          s.add(c)
        focusManager().handleComposingEvent(s, int(te.start))
        binding.needsRepaint = true
      of DropFile:
        let de = cast[DropEventPtr](addr ev)
        if not de.file.isNil:
          let path = $de.file
          dispatchFileDrop(path)
          # SDL allocates the string; we free it.
          sdl2.freeClipboardText(de.file)
      of TextInput:
        let te = cast[TextInputEventPtr](addr ev)
        # The text is a NUL-terminated UTF-8 string in a fixed
        # 32-byte buffer.
        var s = newString(0)
        for i in 0 ..< 32:
          let c = te.text[i]
          if c == '\0': break
          s.add(c)
        if s.len > 0:
          let kev = KeyEvent(kind: keDown, text: s)
          binding.dispatchKey(kev)
          if focusManager().handleKeyEvent(kev):
            binding.needsRepaint = true
      else: discard

    # Drain pointer events into gesture detectors. May enqueue dirty roots
    # via setState callbacks.
    processPointerEvents(binding)

    # Pump async network-image fetches. If a worker thread finished a
    # fetch since the last frame, this bumps the trigger ValueNotifier
    # so subscribed widgets rebuild.
    pumpNetworkImageEvents()

    # Rebuild dirty subtrees. Snapshot and clear FIRST because
    # rebuildElement can add to dirtyRoots (via InheritedWidget
    # notifications that propagate to descendants, or setState
    # callbacks fired by listeners during the rebuild). Iterating
    # the live seq while it grows triggers Nim's items() length
    # assertion and crashes.
    #
    # Newly-added dirty roots get processed on the next frame,
    # which is what Flutter's pipeline does too (microtasks +
    # frame scheduling).
    if binding.dirtyRoots.len > 0:
      let pending = binding.dirtyRoots
      binding.dirtyRoots.setLen(0)
      for r in pending:
        rebuildElement(r)
      runLayout(rootElement, tightFor(binding.surfaceSize))
      canvas.clear(0xFFFFFFFF'u32)
      runPaint(rootElement, canvas)
      canvas.present()
      binding.needsRepaint = false
    elif binding.needsRepaint:
      # Paint-only pass for scroll and other layout-stable changes.
      canvas.clear(0xFFFFFFFF'u32)
      runPaint(rootElement, canvas)
      canvas.present()
      binding.needsRepaint = false
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
          let pending2 = binding.dirtyRoots
          binding.dirtyRoots.setLen(0)
          for r in pending2: rebuildElement(r)
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
