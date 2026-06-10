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
import flit/foundation/layer
import flit/foundation/focus
import flit/foundation/semantics
import flit/rendering/harfbuzz
import flit/rendering/canvas_gpu
import flit/rendering/canvas_gl
import flit/rendering/glyph_atlas
import flit/rendering/raster_pool
import flit/rendering/text
import flit/rendering/decoration
when not defined(js):
  import flit/rendering/bundled_font
import flit/rendering/proxy_box
import flit/rendering/flex
import flit/rendering/stack
import flit/rendering/sliver_list
import flit/rendering/viewport
import flit/widgets/basic
import flit/widgets/lazy_list
import flit/widgets/text_field
import flit/widgets/image_widget
import flit/widgets/transitions
import flit/widgets/navigator as nav_widget
import flit/widgets/form_widget
import flit/widgets/directionality
import flit/widgets/drag_drop
import flit/widgets/menu
import flit/widgets/pickers
import flit/widgets/icon as icon_widget
import flit/widgets/dropdown
import flit/widgets/network_image
import flit/gestures/detector
import flit/gestures/multitouch
import flit/animation/animation
import flit/platform/native_dialogs
import flit/platform/file_picker
import flit/platform/image_clipboard
import flit/platform/system_tray
import flit/platform/a11y_bridge
import flit/platform/notifications
import flit/platform/spellcheck
import flit/platform/haptics
import flit/platform/system_state
import flit/platform/locale_format
when not defined(js):
  import flit/platform/window_decorations
  import flit/platform/desktop/multi_window
import flit/material/material
import flit/material/theme
import flit/cupertino/cupertino
import flit/app

export widget, key, render_object, geometry, color, diagnostics, binding,
       runtime, listenable, layer, focus, semantics, harfbuzz, canvas_gpu,
       canvas_gl, glyph_atlas, raster_pool, text, decoration, proxy_box,
       flex, stack, sliver_list, viewport, basic, lazy_list, text_field, image_widget,
       transitions, nav_widget, form_widget, directionality,
       drag_drop, menu, pickers, icon_widget, dropdown, network_image,
       detector, multitouch, animation,
       native_dialogs, file_picker, image_clipboard, system_tray,
       a11y_bridge, notifications, spellcheck, haptics, system_state,
       locale_format,
       material, theme, cupertino, app

when not defined(js):
  export window_decorations, multi_window, bundled_font
