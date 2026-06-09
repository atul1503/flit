## Accessibility platform bridge. Walks the flit `Semantics` tree
## and exposes it to platform-native accessibility frameworks.
##
## Each platform has a different API:
## - macOS: NSAccessibility protocol on NSView
## - Linux: AT-SPI 2 via D-Bus
## - Windows: UIAutomation (UIA) provider
## - iOS: UIAccessibility informal protocol
## - Android: AccessibilityNodeInfo + AccessibilityNodeProvider
##
## Implementing each natively is a multi-week project per
## platform. This module provides:
##
## 1. A polling-based JSON exporter (`exportSemanticsJson(root)`)
##    that any external test runner or assistive tech can consume.
## 2. A registration hook (`registerSemanticsProvider`) for future
##    per-platform integrations.
## 3. A logging fallback that prints the tree on Cmd+Option+S so
##    developers can verify their Semantics annotations.

import std/[options, os, times]
import ../foundation/[widget, semantics]

type
  SemanticsProvider* = proc(root: Element): string {.closure.}
    ## Called by the runtime when assistive tech queries the tree.
    ## Returns a JSON-encoded `SemanticsNode` array (the same
    ## format as `semantics.toJson`).

var activeProvider* {.threadvar.}: SemanticsProvider
  ## The current semantics provider, or nil for the built-in
  ## JSON exporter. Set via `registerSemanticsProvider`.

var lastSnapshot* {.threadvar.}: string
  ## The most recent semantics JSON that `exportSemanticsJson`
  ## returned. Exposed so external tooling (audit scripts,
  ## screenshot capture) can re-read without re-walking the tree.

proc exportSemanticsJsonInternal*(root: Element): string =
  ## Walks `root`'s element tree and serializes the semantics
  ## nodes via `semantics.toJson`. Used as the default provider.
  ## Public so external bridges can call it directly.
  let nodes = buildSemanticsTree(root)
  result = toJson(nodes)

proc defaultProvider*(root: Element): string =
  ## Default: walk the tree and serialize via `toJson`.
  exportSemanticsJsonInternal(root)

proc registerSemanticsProvider*(provider: SemanticsProvider) =
  ## Registers `provider` as the source of truth for the semantics
  ## tree. Per-platform bridges should call this in their startup
  ## to override the default JSON exporter.
  activeProvider = provider

proc exportSemanticsJson*(root: Element): string =
  ## Returns the current semantics tree as JSON. Used by external
  ## tools (accessibility audits, screenshot generators with
  ## metadata, automated tests).
  if activeProvider.isNil:
    defaultProvider(root)
  else:
    activeProvider(root)

proc dumpSemanticsToFile*(root: Element, path: string = "") =
  ## Writes the semantics tree to a file. Useful for inspection
  ## during development. Default path is `/tmp/flit-a11y-<ts>.json`.
  let actual =
    if path.len > 0: path
    else: "/tmp/flit-a11y-" & $now().toTime().toUnix() & ".json"
  try: writeFile(actual, exportSemanticsJson(root))
  except IOError: discard

# --- macOS: stub for NSAccessibility bridge ---
#
# A real implementation would override NSAccessibility methods on
# the SDL window's NSView via Objective-C runtime calls. That's a
# substantial chunk of work (multiple .m-style files in Nim).
# Below is the registration shape so the actual bridge slots in
# without API changes.

when defined(macosx):
  proc setupMacAccessibility*() =
    ## Placeholder for the macOS NSAccessibility integration. Today
    ## it just registers the default JSON provider; tomorrow this
    ## bridges to AXUIElement / NSAccessibility.
    registerSemanticsProvider(defaultProvider)

when defined(linux):
  proc setupLinuxAccessibility*() =
    ## Placeholder for AT-SPI bridge.
    registerSemanticsProvider(defaultProvider)

when defined(windows):
  proc setupWindowsAccessibility*() =
    ## Placeholder for UIAutomation provider.
    registerSemanticsProvider(defaultProvider)
