## Directionality: an InheritedWidget that propagates a text
## direction (left-to-right or right-to-left) down the widget tree.
## Widgets read it via `textDirectionOf(ctx)`; layout widgets that
## care (Row, Text, Align with start/end alignments) honor it.
##
## flit's existing layout widgets are all written in LTR-first
## terms. Directionality lets you flip a subtree to RTL without
## changing any widget code, and is the bedrock of any
## internationalized app.

import ../foundation/[widget, key, geometry]

# `TextDirection` (with `tdLtr` / `tdRtl`) is defined in
# `foundation/geometry`; we re-use it here so widgets and the
# geometry layer agree on a single definition.

type
  Directionality* = ref object of InheritedWidget
    ## Provides a `TextDirection` to its subtree. Read via
    ## `textDirectionOf(ctx)`; defaults to `tdLtr` when no
    ## ancestor is found.
    direction*: TextDirection

method widgetTypeName*(w: Directionality): string = "Directionality"
method createElement*(w: Directionality): Element = newElement(ekInherited, w)
method updateShouldNotify*(new, old: Directionality): bool =
  new.direction != old.direction

proc directionality*(direction: TextDirection, child: Widget,
                     key: Key = nil): Directionality =
  ## Wraps `child` in a directionality scope.
  ##
  ## Inputs:
  ## - `direction`: `tdLtr` or `tdRtl`.
  ## - `child`: the subtree that should observe this direction.
  ## - `key`: reconciliation key.
  Directionality(key: key, child: child, direction: direction)

proc textDirectionOf*(ctx: BuildContext): TextDirection =
  ## Returns the nearest enclosing text direction, or `tdLtr` if
  ## none is set. Subscribes the calling element to the
  ## `Directionality` so it rebuilds when the direction changes.
  let d = dependOnInheritedOfType[Directionality](ctx)
  if d.isNil: tdLtr else: d.direction
