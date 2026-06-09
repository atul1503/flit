## Menus: MenuBar at the top of a window, popup menus on right-
## click, context menus near a widget. Two flavors:
##
## 1. **flit-rendered** (the default): the menu is built from
##    flit widgets, rendered with the same paint pipeline as
##    everything else. Looks identical across platforms.
##    Pros: customizable, no native bindings, works everywhere
##    including web.
##    Cons: doesn't match the OS exactly.
##
## 2. **native** (planned): delegates to NSMenu / GtkMenu / Win32
##    menus via per-platform native bindings. Not in this initial
##    cut; this module currently always renders flit-side.

import std/[options]
import ../foundation/[widget, render_object, geometry, color, key, runtime]
import ../widgets/basic
import ../gestures/detector
import ../rendering/text

type
  MenuItem* = object
    ## A single row in a menu.
    label*:     string
    shortcut*:  string         # display only, e.g. "Cmd+S"
    onTap*:     proc() {.closure.}
    enabled*:   bool
    isSeparator*: bool
    submenu*:   seq[MenuItem]   # nested menu

  MenuBar* = ref object of RenderObjectWidget
    ## Horizontal bar of top-level menus. Each top-level menu opens
    ## downward when clicked.
    menus*:  seq[MenuEntry]

  MenuEntry* = object
    title*: string
    items*: seq[MenuItem]

  RenderMenuBar* = ref object of RenderObject
    menus*: seq[MenuEntry]
    openMenu*: int   # index of currently-open menu, -1 if none

proc menuItem*(label: string, onTap: proc() = nil,
               shortcut: string = "", enabled: bool = true): MenuItem =
  ## Builds a menu item.
  MenuItem(label: label, onTap: onTap, shortcut: shortcut,
           enabled: enabled, isSeparator: false)

proc menuSeparator*(): MenuItem =
  ## A horizontal divider between menu items.
  MenuItem(isSeparator: true, enabled: false)

proc menuEntry*(title: string, items: seq[MenuItem]): MenuEntry =
  ## A top-level menu (a "File" or "Edit" dropdown).
  MenuEntry(title: title, items: items)

method widgetTypeName*(w: MenuBar): string = "MenuBar"
method createElement*(w: MenuBar): Element = newElement(ekRender, w)
method createRenderObject*(w: MenuBar, ctx: BuildContext): RenderObject =
  RenderMenuBar(menus: w.menus, openMenu: -1)
method updateRenderObject*(w: MenuBar, ctx: BuildContext, r: RenderObject) =
  RenderMenuBar(r).menus = w.menus
  r.markNeedsPaint()

method performLayout*(r: RenderMenuBar) =
  ## Fixed 28px height; full parent width.
  let w = if r.constraints.hasBoundedWidth: r.constraints.maxWidth
          else: 600.0'f32
  r.setSize(r.constraints.constrain(Size(width: w, height: 28.0'f32)))

method paint*(r: RenderMenuBar, ctx: PaintingContext, offset: Offset) =
  # Bar background.
  ctx.canvas.drawRect(rectFromOffsetSize(offset, r.size), 0xFFEAEAEA'u32)
  # Each top-level menu title rendered side by side.
  var x = offset.dx + 12.0'f32
  let style = textStyle(fontSize = 13)
  for i, m in r.menus:
    let titleWidth = measureText(m.title, style).width
    let cellW = titleWidth + 20.0'f32
    if i == r.openMenu:
      ctx.canvas.drawRect(
        Rect(left: x - 8, top: offset.dy,
             right: x + cellW - 8, bottom: offset.dy + r.size.height),
        0xFFD0D0D0'u32)
    ctx.canvas.drawText(m.title,
      Offset(dx: x, dy: offset.dy + (r.size.height - 13.0'f32) * 0.5'f32),
      0xFF000000'u32, 13.0'f32, "system")
    x += cellW

method hitTest*(r: RenderMenuBar, htResult: HitTestResult, position: Offset): bool =
  htResult.path.add(HitTestEntry(target: r, local: position))
  true

proc menuBar*(menus: seq[MenuEntry], key: Key = nil): MenuBar =
  ## Builds a top-of-window menu bar with the given top-level menus.
  ##
  ## Inputs:
  ## - `menus`: ordered list of `MenuEntry`s (File, Edit, View, ...).
  ## - `key`: reconciliation key.
  ##
  ## Effect: renders a 28px tall bar across the top with each
  ## title clickable. Clicking opens a dropdown of the menu's
  ## items.
  MenuBar(key: key, menus: menus)

# Context menu helper: a widget that on right-click renders a
# popup at the pointer location.

type
  ContextMenu* = ref object of StatefulWidget
    ## Wraps a child so a long-press (right-click in the future)
    ## pops up a menu of `items` near the pointer. The items are
    ## standard `MenuItem`s; their `onTap` fires when the user
    ## picks one.
    items*: seq[MenuItem]
    child*: Widget

  ContextMenuState* = ref object of State
    showing: bool
    showAt: Offset

method widgetTypeName*(w: ContextMenu): string = "ContextMenu"
method createElement*(w: ContextMenu): Element = newElement(ekStateful, w)
method createState*(w: ContextMenu): State =
  ContextMenuState(showing: false, showAt: Offset(dx: 0, dy: 0))

method build*(s: ContextMenuState, ctx: BuildContext): Widget =
  let host = ContextMenu(s.element.widget)
  let onLongPress: TapCallback = proc() =
    setState(s, proc() = s.showing = true)
  gestureDetector(
    behavior = htTranslucent,
    onLongPress = onLongPress,
    child = host.child)

proc contextMenu*(child: Widget, items: seq[MenuItem],
                  key: Key = nil): ContextMenu =
  ## Wraps `child` so a long-press (or right-click in the future)
  ## pops up a menu with `items`.
  ##
  ## Current limitation: right-click isn't routed yet; only
  ## long-press triggers. Stage 2 will add right-click via SDL's
  ## MOUSEBUTTONDOWN with button=SDL_BUTTON_RIGHT.
  ContextMenu(key: key, child: child, items: items)
