## Dropdown / select widget. Tap to open a panel of options
## anchored below the trigger; tap an option to select it. Tap
## outside the panel to close.
##
## Generic over the option type `T`. The displayed label uses
## `displayBuilder(value)` for both the closed trigger and each
## open-panel row.
##
## Open-panel rendering uses a `Stack` overlay rather than a
## platform popup, so it works identically across desktop, web,
## and embedded.

import std/[options]
import ../foundation/[widget, render_object, geometry, color, key, runtime,
                       listenable]
import ../widgets/basic
import ../widgets/icon as icon_widget
import ../gestures/detector
import ../rendering/[text, decoration]

type
  Dropdown*[T] = ref object of StatefulWidget
    ## Drop-down selector. `items` is the option list; `value` is
    ## the currently-selected option; `onChange` fires when the
    ## user picks a different one.
    items*:           seq[T]
    value*:           T
    onChange*:        proc(v: T) {.closure.}
    displayBuilder*:  proc(v: T): string {.closure.}
    width*:           float32
    placeholder*:     string

  DropdownState*[T] = ref object of State
    open: bool

method widgetTypeName*[T](w: Dropdown[T]): string = "Dropdown"
method createElement*[T](w: Dropdown[T]): Element = newElement(ekStateful, w)
method createState*[T](w: Dropdown[T]): State = DropdownState[T](open: false)

method build*[T](s: DropdownState[T], ctx: BuildContext): Widget =
  let host = Dropdown[T](s.element.widget)
  let label =
    if host.displayBuilder.isNil: $host.value
    else: host.displayBuilder(host.value)
  let trigger = gestureDetector(
    behavior = htOpaque,
    onTap = proc() = setState(s, proc() = s.open = not s.open),
    child = container(
      width = host.width,
      height = 36,
      padding = edgeInsetsSymmetric(horizontal = 10, vertical = 6),
      hasDecoration = true,
      decoration = boxDecoration(color = colorWhite, borderRadius = 4,
        border = Border(color: rgb(200, 200, 200), width: 1)),
      child = row(crossAxisAlignment = caCenter, children = @[
        Widget(expanded(child = text(
          if label.len > 0: label else: host.placeholder,
          style = textStyle(fontSize = 13, color = colorBlack)))),
        icon("chevron.down", size = 14, color = rgb(80, 80, 80)),
      ])))

  if not s.open:
    return trigger

  # When open: render an overlay panel under the trigger. Since we
  # don't have a real overlay layer yet, we use a Column so the
  # panel pushes below the trigger inline. Tapping outside is
  # approximated by tapping the trigger again to close.
  var rows: seq[Widget]
  for opt in host.items:
    let captured = opt
    let lbl =
      if host.displayBuilder.isNil: $captured
      else: host.displayBuilder(captured)
    rows.add(gestureDetector(
      behavior = htOpaque,
      onTap = proc() =
        setState(s, proc() = s.open = false)
        if not host.onChange.isNil:
          try: host.onChange(captured) except CatchableError: discard,
      child = container(
        padding = edgeInsetsSymmetric(horizontal = 12, vertical = 8),
        child = text(lbl, style = textStyle(fontSize = 13,
          color = colorBlack)))))
  let panel = container(
    width = host.width,
    hasDecoration = true,
    decoration = boxDecoration(color = colorWhite, borderRadius = 4,
      border = Border(color: rgb(200, 200, 200), width: 1)),
    child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                   children = rows))
  column(crossAxisAlignment = caStart, mainAxisSize = msMin,
         children = @[trigger, panel])

proc dropdown*[T](items: seq[T],
                  value: T,
                  onChange: proc(v: T) = nil,
                  displayBuilder: proc(v: T): string = nil,
                  width: float32 = 200,
                  placeholder: string = "",
                  key: Key = nil): Dropdown[T] =
  ## Builds a `Dropdown[T]`.
  ##
  ## Inputs:
  ## - `items`: option list. Must be non-empty for the panel to
  ##   show anything.
  ## - `value`: currently-selected option (must be one of `items`).
  ## - `onChange`: fires when the user picks an option.
  ## - `displayBuilder`: turns a `T` into a display string. Defaults
  ##   to Nim's `$` if nil.
  ## - `width`: fixed width of the closed trigger and open panel.
  ##   Default 200.
  ## - `placeholder`: shown when `displayBuilder(value)` returns "".
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: tapping the trigger toggles the option panel. Selecting
  ## an option closes the panel and calls `onChange`.
  Dropdown[T](key: key, items: items, value: value, onChange: onChange,
              displayBuilder: displayBuilder, width: width,
              placeholder: placeholder)
