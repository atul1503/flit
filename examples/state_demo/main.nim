## ValueNotifier + ListenableBuilder demo. Shows how shared mutable
## state hooks up to multiple watcher widgets, and how updates from
## one widget reach all watchers without touching the rest of the
## tree.
##
## Run: `nim c -d:release -o:bin/state_demo examples/state_demo/main.nim`
##      then `DYLD_LIBRARY_PATH=/opt/homebrew/lib ./bin/state_demo`

import ../../src/flit

# 1. Declare the shared state - just plain ValueNotifiers at module
#    scope. No globals magic, no provider tree, no inheritance.

let userName = newValueNotifier("Atul")
let cartItemCount = newValueNotifier(0)

# 2. Build the UI. Anywhere we want to reflect a notifier's value,
#    we wrap that part of the tree in listenableBuilder. The builder
#    proc receives the current value on every rebuild.

type
  StateDemo* = ref object of StatelessWidget

method widgetTypeName*(w: StateDemo): string = "StateDemo"
method createElement*(w: StateDemo): Element = newElement(ekStateless, w)
method build*(w: StateDemo, ctx: BuildContext): Widget =
  materialApp(home = scaffold(
    appBar = appBar(
      # AppBar title watches userName. When userName changes,
      # ONLY this title rebuilds - the rest of the app stays put.
      title = listenableBuilder(userName,
        proc(ctx: BuildContext, name: string): Widget =
          text("Hi " & name, style = textStyle(fontSize = 18,
                                               color = colorWhite,
                                               fontWeight = 600))),
      actions = @[
        # The cart badge - a totally different part of the tree -
        # also watches cartItemCount independently.
        Widget(listenableBuilder(cartItemCount,
          proc(ctx: BuildContext, n: int): Widget =
            padding(padding = edgeInsetsSymmetric(horizontal = 16, vertical = 8),
              child = text("Cart: " & $n,
                style = textStyle(fontSize = 14, color = colorWhite)))))]),
    body = padding(padding = edgeInsetsAll(24),
      child = column(mainAxisSize = msMin, crossAxisAlignment = caStart,
                     children = @[
        Widget(text("Two notifiers, two watchers, zero glue code.",
          style = textStyle(fontSize = 14))),
        sizedBox(height = 24),

        # A second watcher of userName, far from the title above.
        # Both rebuild together when userName.value is assigned.
        listenableBuilder(userName,
          proc(ctx: BuildContext, name: string): Widget =
            text("Current user (echo): " & name,
                 style = textStyle(fontSize = 16))),
        sizedBox(height = 16),

        # Buttons that mutate the notifiers. Note that these
        # buttons are NOT inside any listenableBuilder - tapping
        # them does NOT cause this Column to rebuild. Only the
        # registered watchers rebuild.
        row(mainAxisSize = msMin, children = @[
          Widget(elevatedButton(
            child = text("Rename to Bob",
              style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = proc() = userName.value = "Bob")),
          sizedBox(width = 12),
          elevatedButton(
            child = text("Rename to Carol",
              style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = proc() = userName.value = "Carol"),
        ]),
        sizedBox(height = 24),

        text("Cart controls:", style = textStyle(fontSize = 14)),
        sizedBox(height = 8),
        row(mainAxisSize = msMin, children = @[
          Widget(elevatedButton(
            child = text("Add item",
              style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = proc() = cartItemCount.value = cartItemCount.value + 1)),
          sizedBox(width = 12),
          elevatedButton(
            child = text("Remove item",
              style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = proc() =
              cartItemCount.value = max(0, cartItemCount.value - 1)),
          sizedBox(width = 12),
          textButton(
            child = text("Reset",
              style = textStyle(fontSize = 14,
                                color = currentTheme().colorScheme.primary)),
            onPressed = proc() = cartItemCount.value = 0),
        ]),
      ]))))

when isMainModule: runApp(StateDemo())
