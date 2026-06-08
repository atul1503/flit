## Flit: a Flutter-inspired UI toolkit for Nim.
##
## Quick start:
##
## .. code-block:: nim
##   import flit
##
##   type Counter = ref object of StatefulWidget
##
##   type CounterState = ref object of State
##     count: int
##
##   method createState(w: Counter): State = CounterState()
##   method build(s: CounterState, ctx: BuildContext): Widget =
##     materialApp(home = scaffold(
##       appBar = appBar(title = text("Flit Demo")),
##       body = center(child = column(children = @[
##         text("You pressed the button " & $s.count & " times."),
##         elevatedButton(child = text("Increment"),
##           onPressed = proc() = setState(s, proc() = inc s.count)),
##       ])),
##     ))
##
##   when isMainModule: runApp(Counter())

import flit/foundation/widget
import flit/foundation/key
import flit/foundation/render_object
import flit/foundation/geometry
import flit/foundation/color
import flit/foundation/diagnostics
import flit/foundation/binding
import flit/foundation/runtime
import flit/foundation/listenable
import flit/rendering/text
import flit/rendering/decoration
import flit/rendering/proxy_box
import flit/rendering/flex
import flit/rendering/stack
import flit/widgets/basic
import flit/gestures/detector
import flit/animation/animation
import flit/material/material
import flit/material/theme
import flit/cupertino/cupertino
import flit/app

export widget, key, render_object, geometry, color, diagnostics, binding,
       runtime, listenable, text, decoration, proxy_box, flex, stack, basic,
       detector, animation, material, theme, cupertino, app
