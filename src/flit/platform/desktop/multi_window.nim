## Multi-window support. `openWindow(widget, config)` adds another
## SDL window to the app; each gets its own canvas, binding, and
## event loop. Closing a secondary window leaves the app running;
## closing all windows quits.
##
## The current implementation is single-threaded: every window's
## frame loop runs in the same `runDesktop` main loop, with events
## dispatched by SDL's window ID. The fast paths (layout cache,
## glyph atlas) are per-window, so opening a second window does
## not slow the first one's perf.
##
## This module exposes the window registry; the desktop runner
## iterates windows in its event/paint loop.

when defined(js):
  {.error: "multi-window is not available on the JS backend".}

import sdl2
import std/tables
import ../../foundation/[widget, render_object, binding, geometry, runtime]
import ../../rendering/canvas_sdl

type
  FlitWindow* = ref object
    ## A flit-managed SDL window. The desktop runner iterates a
    ## table of these and ticks each one per frame.
    id*:           uint32
    window*:       WindowPtr
    renderer*:     RendererPtr
    canvas*:       SdlCanvas
    binding*:      Binding
    rootElement*:  Element
    surfaceSize*:  Size
    title*:        string
    onClose*:      proc() {.closure.}

  WindowConfig* = object
    title*: string
    width*, height*: int
    resizable*, highDpi*, vsync*: bool
    fontPath*: string

proc defaultWindowConfig*(): WindowConfig =
  WindowConfig(title: "flit", width: 800, height: 600,
               resizable: true, highDpi: true, vsync: true)

var windows* {.threadvar.}: Table[uint32, FlitWindow]

proc openWindow*(rootWidget: Widget, config: WindowConfig = defaultWindowConfig(),
                 onClose: proc() = nil): FlitWindow =
  ## Opens a new SDL window and mounts `rootWidget` into it. The
  ## returned `FlitWindow` is registered so the desktop runner
  ## picks it up on the next frame.
  ##
  ## Call from a button handler (after `runApp` has started the
  ## main window) to open settings dialogs, secondary editors,
  ## or floating tool palettes.
  var flags: uint32 = SDL_WINDOW_SHOWN
  if config.resizable: flags = flags or SDL_WINDOW_RESIZABLE
  if config.highDpi:   flags = flags or SDL_WINDOW_ALLOW_HIGHDPI
  let win = createWindow(config.title.cstring,
                         SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                         cint(config.width), cint(config.height), flags)
  if win.isNil: return nil
  var rflags: cint = cint(Renderer_Accelerated)
  if config.vsync: rflags = rflags or cint(Renderer_PresentVsync)
  let renderer = createRenderer(win, -1, rflags)
  if renderer.isNil:
    destroy(win); return nil
  let canvas = newSdlCanvas(win, renderer,
                            config.width, config.height,
                            config.fontPath)
  let binding = newBinding(canvas,
                           Size(width: float32(config.width),
                                height: float32(config.height)))
  let rootElement = mountElement(nil, rootWidget, 0)
  binding.rootElement = rootElement
  runLayout(rootElement, tightFor(binding.surfaceSize))
  canvas.clear(0xFFFFFFFF'u32)
  runPaint(rootElement, canvas)
  canvas.present()
  let w = FlitWindow(
    id: getID(win), window: win, renderer: renderer,
    canvas: canvas, binding: binding, rootElement: rootElement,
    surfaceSize: binding.surfaceSize, title: config.title,
    onClose: onClose)
  windows[w.id] = w
  w

proc closeWindow*(w: FlitWindow) =
  ## Closes a window and releases its SDL resources. The runner
  ## stops ticking it. If this was the last window, the app
  ## quits.
  if w.isNil: return
  if not w.onClose.isNil:
    try: w.onClose() except CatchableError: discard
  windows.del(w.id)
  destroy(w.renderer)
  destroy(w.window)

proc findWindow*(id: uint32): FlitWindow =
  ## Looks up a window by SDL window ID. Used by the runner to
  ## dispatch events to the right window.
  if windows.hasKey(id): windows[id] else: nil

proc allWindows*(): seq[FlitWindow] =
  ## Returns every registered window. Used by the runner to tick
  ## every window's frame loop.
  for _, w in windows: result.add(w)

proc windowCount*(): int =
  ## How many windows are currently open. Reaches zero -> app quits.
  windows.len
