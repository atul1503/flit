## Navigator: a stack of routes. Each route is a widget builder.
## The Navigator paints only the topmost route. `push` adds a route;
## `pop` removes the top.
##
## Routes are widgets, not heavyweight Route objects (Flutter has
## both). For the 90% case of "show this screen next, return when
## done", a widget builder is enough.
##
## A global navigator key gives any widget access to push / pop
## without prop-drilling, identical in shape to Flutter's
## `Navigator.of(context)` shortcut.
##
## Public surface:
## - `navigator(initial)`: build a Navigator with an initial route.
## - `Navigator.push(builder)`: push a new route.
## - `Navigator.pop(result)`: pop the top route, optionally returning
##   a result to whoever pushed it.
## - `currentNavigator()`: app-wide handle to the active navigator.

import ../foundation/[widget, render_object, key, runtime]
import ./transitions

type
  RouteBuilder* = proc(): Widget {.closure.}

  NavigatorWidget* = ref object of StatefulWidget
    initialRoute*: RouteBuilder

  NavigatorState* = ref object of State
    stack*:    seq[RouteBuilder]
    results*:  seq[proc(value: pointer) {.closure.}]

  NavigatorHandle* = ref object
    ## Lightweight handle a widget can hold to drive navigation
    ## without referencing the State directly. Becomes invalid
    ## when the navigator is disposed.
    state*: NavigatorState

var activeNavigator*: NavigatorHandle
  ## App-wide handle to the most-recently-mounted Navigator. Read
  ## via `currentNavigator()`. Mounting a second Navigator replaces
  ## the handle; the old one keeps its state but isn't reachable
  ## via the global.

method widgetTypeName*(w: NavigatorWidget): string = "Navigator"
method createElement*(w: NavigatorWidget): Element = newElement(ekStateful, w)
method createState*(w: NavigatorWidget): State =
  NavigatorState(stack: @[w.initialRoute], results: @[])

method initState(s: NavigatorState) =
  activeNavigator = NavigatorHandle(state: s)

method dispose(s: NavigatorState) =
  if not activeNavigator.isNil and activeNavigator.state == s:
    activeNavigator = nil

method build*(s: NavigatorState, ctx: BuildContext): Widget =
  ## Builds and returns the topmost route. Lower routes are not
  ## built or laid out until they become topmost (push pop pattern).
  if s.stack.len == 0: return nil
  s.stack[^1]()

proc push*(h: NavigatorHandle, route: RouteBuilder,
           transition: RouteTransitionKind = trSlideLeft,
           onResult: proc(value: pointer) = nil) =
  ## Pushes `route` onto the stack and rebuilds. `onResult` fires
  ## when this route is popped (the value passed to `pop`).
  ##
  ## `transition` wraps the new route in an animated transition
  ## widget. `trSlideLeft` (the default) matches iOS-style
  ## navigation. `trNone` skips the animation entirely. The
  ## transition runs once on mount; subsequent rebuilds of the
  ## same route do not re-animate.
  if h.isNil or h.state.isNil: return
  let wrapped: RouteBuilder =
    if transition == trNone: route
    else:
      proc(): Widget = withTransition(transition, route())
  setState(h.state, proc() =
    h.state.stack.add(wrapped)
    h.state.results.add(onResult))

proc pop*(h: NavigatorHandle, value: pointer = nil) =
  ## Pops the top route. If the route that pushed it provided an
  ## `onResult`, fires it with `value`.
  if h.isNil or h.state.isNil: return
  if h.state.stack.len <= 1: return  # don't pop the initial route
  setState(h.state, proc() =
    discard h.state.stack.pop()
    if h.state.results.len > 0:
      let onResult = h.state.results.pop()
      if not onResult.isNil:
        try: onResult(value) except CatchableError: discard)

proc popUntil*(h: NavigatorHandle, depth: int) =
  ## Pops until the stack has exactly `depth` routes. Does nothing
  ## if `depth >= current depth`. Useful for "back to home".
  if h.isNil or h.state.isNil: return
  if depth < 1: return
  if h.state.stack.len <= depth: return
  setState(h.state, proc() =
    while h.state.stack.len > depth:
      discard h.state.stack.pop()
      if h.state.results.len > 0:
        discard h.state.results.pop())

proc pushReplacement*(h: NavigatorHandle, route: RouteBuilder) =
  ## Replaces the top route. The replaced route's `onResult` is
  ## NOT called (it didn't pop, it was replaced).
  if h.isNil or h.state.isNil: return
  setState(h.state, proc() =
    if h.state.stack.len > 0:
      h.state.stack[^1] = route
    else:
      h.state.stack.add(route))

proc depth*(h: NavigatorHandle): int =
  ## Current stack depth. 1 means only the initial route is shown.
  if h.isNil or h.state.isNil: 0 else: h.state.stack.len

proc currentNavigator*(): NavigatorHandle =
  ## App-wide active navigator. Use to push or pop from anywhere
  ## without holding a reference. Returns nil if no Navigator is
  ## mounted.
  activeNavigator

proc navigator*(initial: RouteBuilder, key: Key = nil): NavigatorWidget =
  ## Builds a Navigator with `initial` as the bottom of the stack.
  ## Place near the top of your widget tree.
  ##
  ## Inputs:
  ## - `initial`: builder for the initial / home route.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: the topmost route in the stack is rendered. Push and
  ## pop via `currentNavigator().push(...)` / `.pop(...)`.
  NavigatorWidget(key: key, initialRoute: initial)
