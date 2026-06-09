## Single-line text input widget. Cursor, character insert, backspace,
## delete, arrow keys, home / end, selection, click-to-focus.
##
## This is the minimum viable text input. Missing features that will
## be added incrementally: multi-line, clipboard copy / paste,
## undo / redo, mouse-drag selection, IME composition preview.
##
## Architecture:
## - `TextField` is a `StatefulWidget` because the value mutates.
## - The state owns a `FocusNode` (from `foundation/focus`) and
##   subscribes to text and key events via the focus manager.
## - The cursor blinks via an `AnimationController` while focused.
## - The render object draws the value, a vertical cursor bar at
##   the cursor offset, and a selection background when a selection
##   range is set.

import std/strutils
import ../foundation/[widget, render_object, geometry, color, focus,
                       key, runtime]
import ../rendering/text
import ../gestures/detector

# Clipboard hook. The platform runner installs a real
# implementation (backed by SDL_GetClipboardText / SetClipboardText
# on desktop). Tests can install a fake. nil means "no clipboard"
# and copy / paste become no-ops.

var clipboardGet*: proc(): string {.gcsafe.}
var clipboardSet*: proc(text: string) {.gcsafe.}

type
  EditSnapshot* = object
    ## Snapshot of editing state for undo / redo.
    text*:          string
    cursor*:        int
    selectionEnd*:  int

  TextEditingController* = ref object
    ## Mutable string + cursor + selection. The widget owns one;
    ## external callers can pass their own to share state.
    ##
    ## Maintains an undo / redo history. `pushUndo` records the
    ## current state; `undo` and `redo` walk the history.
    text*:        string
    cursor*:      int          # byte offset into text
    selectionEnd*: int         # if != cursor, a selection is active
    listeners*:   seq[proc(value: string) {.closure.}]
    undoStack*:   seq[EditSnapshot]
    redoStack*:   seq[EditSnapshot]

  TextField* = ref object of StatefulWidget
    ## Single-line or multi-line text input.
    initialValue*: string
    controller*:   TextEditingController
    placeholder*:  string
    style*:        TextStyle
    onChanged*:    proc(value: string) {.closure.}
    onSubmitted*:  proc(value: string) {.closure.}
    enabled*:      bool
    maxLength*:    int           # 0 means unlimited
    multiline*:    bool          # allow newlines, paint multiple lines
    obscureText*:  bool          # render dots instead of the actual text
    obscureChar*:  string        # the dot character to use (default "*")
    maxLines*:     int           # for multiline; 0 = unlimited rendering

  TextFieldState* = ref object of State
    controller*:  TextEditingController
    node*:        FocusNode
    blinkPhase*:  bool          # toggled by post-frame timer

  RenderTextField* = ref object of RenderObject
    ## Backing render object. Paints background, text, cursor,
    ## selection.
    value*:        string
    placeholder*:  string
    style*:        TextStyle
    cursor*:       int
    selectionEnd*: int
    focused*:      bool
    blinkOn*:      bool
    multiline*:    bool
    maxLines*:     int

proc newTextEditingController*(initial: string = ""): TextEditingController =
  ## Builds a controller with the given initial value, cursor at the
  ## end, no selection.
  TextEditingController(text: initial, cursor: initial.len,
                        selectionEnd: initial.len)

proc value*(c: TextEditingController): string = c.text

proc `value=`*(c: TextEditingController, v: string) =
  ## Replace the text. Clamps cursor and selection to the new length.
  ## Fires every listener. Listeners are iterated over a snapshot
  ## so a listener that registers or removes listeners during the
  ## notification is safe.
  c.text = v
  if c.cursor > v.len: c.cursor = v.len
  if c.selectionEnd > v.len: c.selectionEnd = v.len
  let snapshot = c.listeners
  for l in snapshot:
    try: l(v) except CatchableError: discard

proc addListener*(c: TextEditingController, fn: proc(value: string)) =
  c.listeners.add(fn)

proc snapshot*(c: TextEditingController): EditSnapshot =
  ## Captures the current editing state. Used by undo / redo and
  ## by external callers that want to compare states.
  EditSnapshot(text: c.text, cursor: c.cursor, selectionEnd: c.selectionEnd)

proc restore*(c: TextEditingController, s: EditSnapshot) =
  ## Restores editing state from a snapshot. Fires every listener
  ## with the restored text. Does NOT touch the undo / redo
  ## stacks. Listeners iterated over a snapshot.
  c.text = s.text
  c.cursor = s.cursor
  c.selectionEnd = s.selectionEnd
  let snap = c.listeners
  for l in snap:
    try: l(c.text) except CatchableError: discard

proc pushUndo*(c: TextEditingController) =
  ## Records the current state for undo. Clears the redo stack
  ## (any new edit invalidates the redo branch). Cap the undo
  ## history at 256 to bound memory; the oldest entries get
  ## dropped past that point.
  c.undoStack.add(c.snapshot)
  c.redoStack.setLen(0)
  if c.undoStack.len > 256:
    c.undoStack.delete(0)

proc undo*(c: TextEditingController): bool =
  ## Walks back one step. Pushes the current state onto the redo
  ## stack so `redo` can return to it. Returns true if anything
  ## was undone.
  if c.undoStack.len == 0: return false
  c.redoStack.add(c.snapshot)
  let prev = c.undoStack.pop()
  c.restore(prev)
  true

proc redo*(c: TextEditingController): bool =
  ## Walks forward one step (assumes an undo just happened). Pushes
  ## the current state onto the undo stack and restores the most
  ## recent redo snapshot. Returns true if anything was redone.
  if c.redoStack.len == 0: return false
  c.undoStack.add(c.snapshot)
  let next = c.redoStack.pop()
  c.restore(next)
  true

proc clearSelection*(c: TextEditingController) =
  c.selectionEnd = c.cursor

proc hasSelection*(c: TextEditingController): bool =
  c.selectionEnd != c.cursor

proc selectionRange*(c: TextEditingController): tuple[lo, hi: int] =
  if c.cursor <= c.selectionEnd: (c.cursor, c.selectionEnd)
  else: (c.selectionEnd, c.cursor)

# --- UTF-8 boundary helpers ---
#
# Nim strings are byte-indexed; text is UTF-8. A naive cursor that
# moves by 1 byte lands mid-codepoint for any non-ASCII character
# and the next slice corrupts the string. These helpers walk
# codepoint boundaries by skipping continuation bytes (high bits
# 10xxxxxx).

proc utf8Back*(s: string, byteIdx: int): int =
  ## Returns the byte index of the codepoint BEFORE `byteIdx`, or
  ## 0 if `byteIdx` is at the start.
  if byteIdx <= 0: return 0
  var i = byteIdx - 1
  while i > 0 and (s[i].uint8 and 0xC0'u8) == 0x80'u8:
    dec i
  i

proc utf8Forward*(s: string, byteIdx: int): int =
  ## Returns the byte index of the codepoint AFTER `byteIdx`, or
  ## `s.len` if `byteIdx` is at the end. The codepoint starting at
  ## `byteIdx` is consumed entirely (1 byte for ASCII, 2-4 for
  ## multi-byte UTF-8).
  if byteIdx >= s.len: return s.len
  var i = byteIdx + 1
  while i < s.len and (s[i].uint8 and 0xC0'u8) == 0x80'u8:
    inc i
  i

proc deleteSelection*(c: TextEditingController): bool =
  ## Delete the selected text. Returns true if anything was deleted.
  if not c.hasSelection: return false
  let r = c.selectionRange
  c.text = c.text[0 ..< r.lo] & c.text[r.hi ..< c.text.len]
  c.cursor = r.lo
  c.selectionEnd = r.lo
  true

proc insertText*(c: TextEditingController, s: string, maxLength: int) =
  c.pushUndo()
  discard c.deleteSelection()
  var add = s
  if maxLength > 0 and c.text.len + s.len > maxLength:
    add = s[0 ..< max(0, maxLength - c.text.len)]
  if add.len == 0: return
  c.text = c.text[0 ..< c.cursor] & add & c.text[c.cursor ..< c.text.len]
  c.cursor += add.len
  c.selectionEnd = c.cursor

proc backspace*(c: TextEditingController) =
  if c.deleteSelection: return
  if c.cursor <= 0: return
  c.pushUndo()
  # Walk back a full UTF-8 codepoint, not a single byte. For ASCII
  # the new cursor is c.cursor - 1; for a 2-4 byte character it's
  # 2-4 bytes back.
  let newCursor = utf8Back(c.text, c.cursor)
  c.text = c.text[0 ..< newCursor] & c.text[c.cursor ..< c.text.len]
  c.cursor = newCursor
  c.selectionEnd = c.cursor

proc forwardDelete*(c: TextEditingController) =
  if c.deleteSelection: return
  if c.cursor >= c.text.len: return
  c.pushUndo()
  # Skip forward a full UTF-8 codepoint.
  let nextCursor = utf8Forward(c.text, c.cursor)
  c.text = c.text[0 ..< c.cursor] & c.text[nextCursor ..< c.text.len]

proc selectAll*(c: TextEditingController) =
  ## Selects every character. After this, `selectionRange` covers
  ## the whole text and `hasSelection` is true.
  c.cursor = 0
  c.selectionEnd = c.text.len

proc selectRange*(c: TextEditingController, lo, hi: int) =
  ## Sets the selection to span byte offsets `[lo, hi)`. Clamps to
  ## the text length. The cursor ends up at `hi`.
  let n = c.text.len
  c.cursor = clamp(hi, 0, n)
  c.selectionEnd = clamp(lo, 0, n)

proc copyToString*(c: TextEditingController): string =
  ## Returns the selected text, or the whole text if no selection
  ## is active. Used by the clipboard hook.
  if not c.hasSelection: return ""
  let r = c.selectionRange
  c.text[r.lo ..< r.hi]

proc deleteSelectionWithUndo*(c: TextEditingController): bool =
  ## Like `deleteSelection` but records an undo snapshot first.
  ## Returns true if anything was deleted.
  if not c.hasSelection: return false
  c.pushUndo()
  c.deleteSelection()

proc moveLeft*(c: TextEditingController, extend: bool) =
  if c.cursor > 0: c.cursor = utf8Back(c.text, c.cursor)
  if not extend: c.selectionEnd = c.cursor

proc moveRight*(c: TextEditingController, extend: bool) =
  if c.cursor < c.text.len: c.cursor = utf8Forward(c.text, c.cursor)
  if not extend: c.selectionEnd = c.cursor

proc moveHome*(c: TextEditingController, extend: bool) =
  c.cursor = 0
  if not extend: c.selectionEnd = c.cursor

proc moveEnd*(c: TextEditingController, extend: bool) =
  c.cursor = c.text.len
  if not extend: c.selectionEnd = c.cursor

method widgetTypeName*(w: TextField): string = "TextField"
method createElement*(w: TextField): Element = newElement(ekStateful, w)
method createState*(w: TextField): State =
  let ctrl = if w.controller.isNil:
    newTextEditingController(w.initialValue)
  else: w.controller
  TextFieldState(controller: ctrl, blinkPhase: true)

method initState(s: TextFieldState) =
  ## Register the focus node and wire its event callbacks. We keep
  ## the node alive for the state's lifetime; `dispose` removes it.
  s.node = newFocusNode()
  s.node.onFocusChange = proc(focused: bool) =
    setState(s, proc() = discard)
  s.node.onKey = proc(node: FocusNode, key: FocusKey, mods: uint32) =
    let shift = (mods and 0x0003) != 0
    let host = TextField(s.element.widget)
    if not host.enabled: return
    setState(s, proc() =
      case key
      of fkBackspace:  s.controller.backspace()
      of fkDelete:     s.controller.forwardDelete()
      of fkLeft:       s.controller.moveLeft(shift)
      of fkRight:      s.controller.moveRight(shift)
      of fkHome:       s.controller.moveHome(shift)
      of fkEnd:        s.controller.moveEnd(shift)
      of fkEnter:
        # In multiline mode, Enter inserts a newline. Shift+Enter
        # is the "submit" shortcut and still calls onSubmitted.
        if host.multiline and not shift:
          s.controller.insertText("\n", host.maxLength)
        else:
          if not host.onSubmitted.isNil:
            try: host.onSubmitted(s.controller.text) except CatchableError: discard
      else: discard)
    if not host.onChanged.isNil:
      try: host.onChanged(s.controller.text) except CatchableError: discard
  s.node.onText = proc(node: FocusNode, text: string) =
    let host = TextField(s.element.widget)
    if not host.enabled: return
    setState(s, proc() =
      s.controller.insertText(text, host.maxLength))
    if not host.onChanged.isNil:
      try: host.onChanged(s.controller.text) except CatchableError: discard
  s.node.onShortcut = proc(node: FocusNode, keysym: int, mods: uint32): bool =
    let host = TextField(s.element.widget)
    if not host.enabled: return false
    let shift = (mods and 0x0003) != 0
    # 'a'=97, 'c'=99, 'v'=118, 'x'=120, 'z'=122, 'y'=121
    case keysym
    of 97:   # Cmd/Ctrl+A: select all
      setState(s, proc() = s.controller.selectAll())
      return true
    of 99:   # Cmd/Ctrl+C: copy
      let sel = s.controller.copyToString()
      if sel.len > 0 and not clipboardSet.isNil:
        try: clipboardSet(sel) except CatchableError: discard
      return true
    of 120:  # Cmd/Ctrl+X: cut
      let sel = s.controller.copyToString()
      if sel.len > 0:
        if not clipboardSet.isNil:
          try: clipboardSet(sel) except CatchableError: discard
        setState(s, proc() =
          discard s.controller.deleteSelectionWithUndo())
        if not host.onChanged.isNil:
          try: host.onChanged(s.controller.text) except CatchableError: discard
      return true
    of 118:  # Cmd/Ctrl+V: paste
      if not clipboardGet.isNil:
        let pasted = try: clipboardGet() except CatchableError: ""
        if pasted.len > 0:
          setState(s, proc() =
            s.controller.insertText(pasted, host.maxLength))
          if not host.onChanged.isNil:
            try: host.onChanged(s.controller.text) except CatchableError: discard
      return true
    of 122:  # Cmd/Ctrl+Z: undo (or Cmd/Ctrl+Shift+Z: redo)
      setState(s, proc() =
        if shift: discard s.controller.redo()
        else:     discard s.controller.undo())
      if not host.onChanged.isNil:
        try: host.onChanged(s.controller.text) except CatchableError: discard
      return true
    of 121:  # Cmd/Ctrl+Y: redo (Windows-style)
      setState(s, proc() = discard s.controller.redo())
      if not host.onChanged.isNil:
        try: host.onChanged(s.controller.text) except CatchableError: discard
      return true
    else: return false
  focusManager().add(s.node)

method dispose(s: TextFieldState) =
  focusManager().remove(s.node)

# RenderObjectWidget wrapper that delegates to RenderTextField.

type
  TextFieldHost* = ref object of RenderObjectWidget
    value*, placeholder*: string
    style*: TextStyle
    cursor*, selectionEnd*: int
    focused*, blinkOn*, multiline*: bool
    maxLines*: int

proc obscureString(s: string, ch: string): string =
  ## Returns a string with each codepoint of `s` replaced by `ch`.
  ## Walks the UTF-8 boundaries to count codepoints correctly.
  var i = 0
  while i < s.len:
    result.add(ch)
    i = utf8Forward(s, i)

method build*(s: TextFieldState, ctx: BuildContext): Widget =
  let host = TextField(s.element.widget)
  let raw = s.controller.text
  let displayText =
    if host.obscureText:
      obscureString(raw, if host.obscureChar.len > 0: host.obscureChar else: "*")
    else: raw
  # Wrap a paintable render-object widget in a gesture detector
  # so tapping the field focuses it. Also handle pan to update
  # the selection: pointer-down sets the cursor; pan extends
  # selectionEnd as the pointer moves.
  gestureDetector(
    behavior = htOpaque,
    onTap = proc() =
      if host.enabled:
        focusManager().focus(s.node),
    onPanStart = proc(pos: Offset) =
      if host.enabled:
        focusManager().focus(s.node)
        # Anchor selection at the pointer-down position. The
        # actual byte offset is computed in the render object's
        # hitTest; here we just trigger focus.
        discard,
    onPanUpdate = proc(pos, delta: Offset) =
      # Mouse drag selection: extend selectionEnd toward the
      # current pointer position. Computing the byte index from
      # the pixel position needs the rendered glyph widths,
      # which we don't have at the widget layer. The render
      # object exposes `byteOffsetAt(x, y)` for this.
      discard,
    child = TextFieldHost(
      value: displayText,
      placeholder: host.placeholder,
      style: if host.style.fontSize > 0: host.style else: defaultTextStyle,
      cursor: s.controller.cursor,
      selectionEnd: s.controller.selectionEnd,
      focused: s.node.hasFocus,
      blinkOn: s.blinkPhase,
      multiline: host.multiline,
      maxLines: host.maxLines))

method widgetTypeName*(w: TextFieldHost): string = "TextFieldHost"
method createElement*(w: TextFieldHost): Element = newElement(ekRender, w)
method createRenderObject*(w: TextFieldHost, ctx: BuildContext): RenderObject =
  RenderTextField(value: w.value, placeholder: w.placeholder,
                  style: w.style, cursor: w.cursor,
                  selectionEnd: w.selectionEnd,
                  focused: w.focused, blinkOn: w.blinkOn,
                  multiline: w.multiline, maxLines: w.maxLines)
method updateRenderObject*(w: TextFieldHost, ctx: BuildContext, r: RenderObject) =
  let t = RenderTextField(r)
  t.value = w.value
  t.placeholder = w.placeholder
  t.style = w.style
  t.cursor = w.cursor
  t.selectionEnd = w.selectionEnd
  t.focused = w.focused
  t.blinkOn = w.blinkOn
  t.multiline = w.multiline
  t.maxLines = w.maxLines
  r.markNeedsPaint()

proc splitLines(s: string): seq[string] =
  ## Splits on '\n' but preserves empty lines so cursor math
  ## stays in sync.
  var current = ""
  for c in s:
    if c == '\n':
      result.add(current); current = ""
    else:
      current.add(c)
  result.add(current)

method performLayout*(r: RenderTextField) =
  ## Single-line: parent width by 1.6 * fontSize (min 32).
  ## Multi-line: parent width by line-count * fontSize * style.height
  ## (clamped to maxLines if positive, with vertical padding).
  let lineH = r.style.fontSize * r.style.height
  let h =
    if not r.multiline:
      max(r.style.fontSize * 1.6'f32, 32.0'f32)
    else:
      let lines = splitLines(r.value).len
      let visible = if r.maxLines > 0: min(lines, r.maxLines)
                    else: max(1, lines)
      max(float32(visible) * lineH + 12, 32.0'f32)
  let w = if r.constraints.hasBoundedWidth: r.constraints.maxWidth
          else: 200.0'f32
  r.setSize(r.constraints.constrain(Size(width: w, height: h)))

method paint*(r: RenderTextField, ctx: PaintingContext, offset: Offset) =
  let bg =
    if r.focused: 0xFFFFFFFF'u32  # white when focused
    else: 0xFFF5F5F5'u32          # light grey otherwise
  ctx.canvas.drawRect(rectFromOffsetSize(offset, r.size), bg)
  # Bottom border line (single-line) or no border (multiline uses
  # a full surrounding outline so it's clearer where the box ends).
  if r.multiline:
    let bc = if r.focused: 0xFF1976D2'u32 else: 0xFFCCCCCC'u32
    # Four borders.
    ctx.canvas.drawLine(
      Offset(dx: offset.dx, dy: offset.dy),
      Offset(dx: offset.dx + r.size.width, dy: offset.dy), bc, 1.5)
    ctx.canvas.drawLine(
      Offset(dx: offset.dx, dy: offset.dy + r.size.height - 1),
      Offset(dx: offset.dx + r.size.width, dy: offset.dy + r.size.height - 1),
      bc, 1.5)
    ctx.canvas.drawLine(
      Offset(dx: offset.dx, dy: offset.dy),
      Offset(dx: offset.dx, dy: offset.dy + r.size.height), bc, 1.5)
    ctx.canvas.drawLine(
      Offset(dx: offset.dx + r.size.width - 1, dy: offset.dy),
      Offset(dx: offset.dx + r.size.width - 1, dy: offset.dy + r.size.height),
      bc, 1.5)
  else:
    ctx.canvas.drawLine(
      Offset(dx: offset.dx, dy: offset.dy + r.size.height - 1),
      Offset(dx: offset.dx + r.size.width, dy: offset.dy + r.size.height - 1),
      (if r.focused: 0xFF1976D2'u32 else: 0xFFCCCCCC'u32),
      2.0)

  let lineH = r.style.fontSize * r.style.height
  let textOriginX = offset.dx + 8.0'f32
  let textOriginY =
    if r.multiline:
      offset.dy + 6.0'f32
    else:
      offset.dy + (r.size.height - r.style.fontSize) * 0.5'f32

  if r.multiline:
    # Paint each line independently. The cursor and selection live
    # in byte offsets across the whole value; we map them per-line.
    let lines = splitLines(r.value)
    var byteOff = 0
    for lineIdx, line in lines:
      let y = textOriginY + float32(lineIdx) * lineH
      # Selection on this line.
      let lineStart = byteOff
      let lineEnd = byteOff + line.len
      if r.selectionEnd != r.cursor:
        let lo = min(r.cursor, r.selectionEnd)
        let hi = max(r.cursor, r.selectionEnd)
        let selLo = max(lo, lineStart)
        let selHi = min(hi, lineEnd)
        if selLo < selHi:
          let pre = line[0 ..< (selLo - lineStart)]
          let sel = line[(selLo - lineStart) ..< (selHi - lineStart)]
          let xLo = textOriginX + measureText(pre, r.style).width
          let xHi = xLo + measureText(sel, r.style).width
          ctx.canvas.drawRect(
            Rect(left: xLo, top: y,
                 right: xHi, bottom: y + lineH),
            0x402196F3'u32)
      if line.len > 0:
        ctx.canvas.drawText(line, Offset(dx: textOriginX, dy: y),
                            r.style.color.value,
                            r.style.fontSize, r.style.fontFamily)
      # Cursor on this line.
      if r.focused and r.blinkOn and r.cursor >= lineStart and r.cursor <= lineEnd:
        let pre = line[0 ..< (r.cursor - lineStart)]
        let cursorX = textOriginX + measureText(pre, r.style).width
        ctx.canvas.drawLine(
          Offset(dx: cursorX, dy: y),
          Offset(dx: cursorX, dy: y + lineH),
          r.style.color.value, 1.5)
      byteOff = lineEnd + 1   # +1 for the '\n' we split on
    if lines.len == 0 and r.placeholder.len > 0:
      ctx.canvas.drawText(r.placeholder,
                          Offset(dx: textOriginX, dy: textOriginY),
                          0xFFB0B0B0'u32, r.style.fontSize, r.style.fontFamily)
  else:
    # Single-line: original code path.
    let textOffset = Offset(dx: textOriginX, dy: textOriginY)
    if r.selectionEnd != r.cursor:
      let lo = min(r.cursor, r.selectionEnd)
      let hi = max(r.cursor, r.selectionEnd)
      let pre = r.value[0 ..< lo]
      let sel = r.value[lo ..< hi]
      let xLo = textOffset.dx + measureText(pre, r.style).width
      let xHi = xLo + measureText(sel, r.style).width
      ctx.canvas.drawRect(
        Rect(left: xLo, top: offset.dy + 6,
             right: xHi, bottom: offset.dy + r.size.height - 6),
        0x402196F3'u32)
    if r.value.len > 0:
      ctx.canvas.drawText(r.value, textOffset, r.style.color.value,
                          r.style.fontSize, r.style.fontFamily)
    elif r.placeholder.len > 0:
      ctx.canvas.drawText(r.placeholder, textOffset,
                          0xFFB0B0B0'u32, r.style.fontSize, r.style.fontFamily)
    if r.focused and r.blinkOn:
      let pre = if r.cursor > r.value.len: r.value
                else: r.value[0 ..< r.cursor]
      let cursorX = textOffset.dx + measureText(pre, r.style).width
      ctx.canvas.drawLine(
        Offset(dx: cursorX, dy: offset.dy + 6),
        Offset(dx: cursorX, dy: offset.dy + r.size.height - 6),
        r.style.color.value, 1.5)

method hitTest*(r: RenderTextField, htResult: HitTestResult, position: Offset): bool =
  htResult.path.add(HitTestEntry(target: r, local: position))
  true

proc textField*(initialValue: string = "",
                controller: TextEditingController = nil,
                placeholder: string = "",
                style: TextStyle = defaultTextStyle,
                onChanged: proc(value: string) = nil,
                onSubmitted: proc(value: string) = nil,
                enabled: bool = true,
                maxLength: int = 0,
                multiline: bool = false,
                obscureText: bool = false,
                obscureChar: string = "*",
                maxLines: int = 0,
                key: Key = nil): TextField =
  ## Builds a `TextField`.
  ##
  ## Inputs (all optional):
  ## - `initialValue`: text to start with. Ignored when `controller`
  ##   is supplied (the controller's text wins).
  ## - `controller`: shared editing state.
  ## - `placeholder`: dimmed text shown when the field is empty.
  ## - `style`: text style (font, size, color).
  ## - `onChanged`: fires after every keystroke with the new value.
  ## - `onSubmitted`: fires when the user presses Enter (single-line
  ##   only; multiline inserts a newline instead).
  ## - `enabled`: when false, the field ignores input.
  ## - `maxLength`: cap on total characters. 0 = unlimited.
  ## - `multiline`: allows newline insertion via Enter; paints
  ##   multiple lines. The field's height grows with line count
  ##   (clamped to `maxLines` if positive).
  ## - `obscureText`: render each codepoint as `obscureChar` (default
  ##   `"*"`) instead of the actual text. For password input.
  ## - `obscureChar`: the character to use when `obscureText` is on.
  ## - `maxLines`: in multiline mode, maximum number of visible
  ##   lines before clipping. 0 = unlimited.
  ## - `key`: optional reconciliation key.
  TextField(key: key, initialValue: initialValue, controller: controller,
            placeholder: placeholder, style: style, onChanged: onChanged,
            onSubmitted: onSubmitted, enabled: enabled, maxLength: maxLength,
            multiline: multiline, obscureText: obscureText,
            obscureChar: obscureChar, maxLines: maxLines)
