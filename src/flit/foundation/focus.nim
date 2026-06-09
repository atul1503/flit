## Keyboard focus management. The `FocusManager` owns the currently-
## focused `FocusNode`; key events dispatched via the binding route
## to that node's handler. Widgets that need keyboard input
## (`TextField`, custom interactive widgets) own a `FocusNode` and
## register it with the manager when they want focus.
##
## Tab cycles focus through registered nodes in registration order.
## Shift+Tab cycles backwards. The manager handles this automatically
## as long as the runner forwards `Tab` key events through
## `handleKeyEvent`.
##
## This is intentionally simpler than Flutter's full FocusScope tree.
## A single flat list of focusables is enough for ~99% of UI work
## and avoids the complexity of nested focus scopes for now.

import std/options
import ./binding

type
  FocusKey* = enum
    ## Logical key codes the focus system understands. The platform
    ## runner translates raw scancodes into these before calling
    ## `handleKeyEvent`. SDL's scancode and keysym values are kept
    ## in sync via the runner.
    fkUnknown, fkBackspace, fkDelete, fkEnter, fkEscape,
    fkTab, fkLeft, fkRight, fkUp, fkDown, fkHome, fkEnd,
    fkPageUp, fkPageDown

  KeyHandler* = proc(node: FocusNode, key: FocusKey, modifiers: uint32) {.closure.}
  TextHandler* = proc(node: FocusNode, text: string) {.closure.}
  ShortcutHandler* = proc(node: FocusNode, keysym: int, modifiers: uint32): bool {.closure.}
    ## Returns true if the shortcut was consumed.
  ComposingHandler* = proc(node: FocusNode, composing: string, cursorPos: int) {.closure.}
    ## Called during IME composition. `composing` is the in-progress
    ## text (e.g. partial CJK input); `cursorPos` is the byte offset
    ## within `composing` where the IME cursor is. Empty string
    ## means composition ended.

  FocusNode* = ref object
    ## A focusable target. The owner widget creates one in `initState`,
    ## registers it via `manager.add`, and supplies `onKey`, `onText`,
    ## and (optionally) `onShortcut` callbacks to receive input.
    ##
    ## `hasFocus` is true while this node is the manager's
    ## `current`. `onFocusChange` fires whenever that transitions.
    onKey*:         KeyHandler
    onText*:        TextHandler
    onShortcut*:    ShortcutHandler
    onComposing*:   ComposingHandler
    onFocusChange*: proc(focused: bool) {.closure.}
    hasFocus*:      bool
    enabled*:       bool

  FocusManager* = ref object
    ## App-wide focus state. One per binding, accessed via
    ## `binding.focusManager`. The manager owns the focus traversal
    ## order (`nodes`) and the currently-focused node (`current`).
    nodes*:   seq[FocusNode]
    current*: FocusNode

# Allocate the manager lazily so apps that don't use focus don't
# pay the cost.

var globalFocus*: FocusManager

proc focusManager*(): FocusManager =
  ## Returns the app-wide focus manager, creating it on first
  ## access. Safe to call from anywhere.
  if globalFocus.isNil:
    globalFocus = FocusManager()
  globalFocus

proc newFocusNode*(onKey: KeyHandler = nil,
                  onText: TextHandler = nil,
                  onShortcut: ShortcutHandler = nil,
                  onFocusChange: proc(focused: bool) = nil): FocusNode =
  ## Constructs a fresh focus node. Set callbacks for the events
  ## you care about; nil callbacks are ignored.
  FocusNode(onKey: onKey, onText: onText, onShortcut: onShortcut,
            onFocusChange: onFocusChange,
            hasFocus: false, enabled: true)

proc add*(m: FocusManager, node: FocusNode) =
  ## Registers `node` with the manager. Idempotent. Adds at the
  ## end of the traversal order.
  if node.isNil: return
  for n in m.nodes:
    if n == node: return
  m.nodes.add(node)

proc remove*(m: FocusManager, node: FocusNode) =
  ## Removes `node` from the manager. Clears focus if the removed
  ## node was focused.
  if node.isNil: return
  var keep: seq[FocusNode]
  for n in m.nodes:
    if n != node: keep.add(n)
  m.nodes = keep
  if m.current == node:
    m.current = nil
    node.hasFocus = false
    if not node.onFocusChange.isNil:
      try: node.onFocusChange(false) except CatchableError: discard

proc focus*(m: FocusManager, node: FocusNode) =
  ## Transfers focus to `node`. The previously focused node, if
  ## any, gets `hasFocus = false` and its `onFocusChange(false)`
  ## fires.
  if node.isNil or not node.enabled: return
  if m.current == node: return
  if not m.current.isNil:
    m.current.hasFocus = false
    if not m.current.onFocusChange.isNil:
      try: m.current.onFocusChange(false) except CatchableError: discard
  m.current = node
  node.hasFocus = true
  if not node.onFocusChange.isNil:
    try: node.onFocusChange(true) except CatchableError: discard

proc unfocus*(m: FocusManager) =
  ## Drops focus from whatever currently has it. Useful when the
  ## user clicks outside any focusable widget.
  if m.current.isNil: return
  let n = m.current
  m.current = nil
  n.hasFocus = false
  if not n.onFocusChange.isNil:
    try: n.onFocusChange(false) except CatchableError: discard

proc next*(m: FocusManager) =
  ## Moves focus to the next enabled node in registration order.
  ## Wraps around. No-op if no focusables are registered.
  if m.nodes.len == 0: return
  var idx = -1
  for i, n in m.nodes:
    if n == m.current:
      idx = i
      break
  for step in 1 .. m.nodes.len:
    let candidate = m.nodes[(idx + step) mod m.nodes.len]
    if candidate.enabled:
      m.focus(candidate)
      return

proc prev*(m: FocusManager) =
  ## Reverse of `next`.
  if m.nodes.len == 0: return
  var idx = m.nodes.len
  for i, n in m.nodes:
    if n == m.current:
      idx = i
      break
  for step in 1 .. m.nodes.len:
    let raw = (idx - step) mod m.nodes.len
    let normalized = if raw < 0: raw + m.nodes.len else: raw
    let candidate = m.nodes[normalized]
    if candidate.enabled:
      m.focus(candidate)
      return

proc handleComposingEvent*(m: FocusManager, composing: string, cursorPos: int) =
  ## Routes an IME composition update to the focused node's
  ## `onComposing` callback. Empty string ends composition.
  if m.current.isNil: return
  if m.current.onComposing.isNil: return
  try: m.current.onComposing(m.current, composing, cursorPos)
  except CatchableError: discard

proc handleKeyEvent*(m: FocusManager, ev: KeyEvent): bool =
  ## Routes `ev` to the focused node. Returns true if the event was
  ## consumed by focus traversal or by the focused node. Returns
  ## false if no node was focused or the event should propagate
  ## elsewhere.
  ##
  ## Tab and Shift+Tab are intercepted here for traversal.
  ## Backspace, Delete, Enter, Escape, arrows, Home, End, PgUp,
  ## PgDown are forwarded as `FocusKey` codes to `onKey`. Any
  ## other key that has a `text` field gets forwarded to `onText`.
  if ev.kind != keDown and ev.kind != keRepeat: return false

  # SDL keysym for Tab is 9. Shift modifier mask is 0x0001 (KMOD_LSHIFT)
  # or 0x0002 (KMOD_RSHIFT); we test against the OR.
  if ev.keyCode == 9:
    if (ev.modifiers and 0x0003) != 0: m.prev()
    else: m.next()
    return true

  if m.current.isNil: return false

  # Modifier mask for Ctrl + Cmd (Mac uses Cmd, Linux/Windows use Ctrl).
  # SDL bits: 0x40 = LCtrl, 0x80 = RCtrl, 0x400 = LGui (Mac Cmd),
  # 0x800 = RGui.
  const modMask = uint32(0x40 or 0x80 or 0x400 or 0x800)

  # When a Ctrl or Cmd modifier is pressed and the keysym is a
  # printable ASCII letter, deliver to onShortcut. SDL suppresses
  # TextInput for these combos so we don't double-fire.
  if (ev.modifiers and modMask) != 0 and ev.keyCode in 32..126:
    if not m.current.onShortcut.isNil:
      var consumed = false
      try:
        consumed = m.current.onShortcut(m.current, ev.keyCode, ev.modifiers)
      except CatchableError: discard
      if consumed: return true

  let fk = case ev.keyCode
    of 8: fkBackspace
    of 127: fkDelete
    of 13: fkEnter
    of 27: fkEscape
    of 1073741904: fkLeft   # SDLK_LEFT
    of 1073741903: fkRight  # SDLK_RIGHT
    of 1073741906: fkUp     # SDLK_UP
    of 1073741905: fkDown   # SDLK_DOWN
    of 1073741898: fkHome   # SDLK_HOME
    of 1073741901: fkEnd    # SDLK_END
    of 1073741899: fkPageUp # SDLK_PAGEUP
    of 1073741902: fkPageDown # SDLK_PAGEDOWN
    else: fkUnknown

  if fk != fkUnknown:
    if not m.current.onKey.isNil:
      try: m.current.onKey(m.current, fk, ev.modifiers)
      except CatchableError: discard
    return true

  # Fall through to text input if the event has a printable text
  # component.
  if ev.text.len > 0 and not m.current.onText.isNil:
    try: m.current.onText(m.current, ev.text)
    except CatchableError: discard
    return true

  false
