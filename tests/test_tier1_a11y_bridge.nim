## Accessibility bridge: provider registration + JSON export.

import std/[unittest, strutils]
import ../src/flit/platform/a11y_bridge
import ../src/flit/foundation/[semantics, widget, runtime]
import ../src/flit/widgets/basic

suite "a11y_bridge":
  test "exportSemanticsJson on bare element returns empty array":
    activeProvider = nil
    let root = mountElement(nil, text("hi"), 0)
    let j = exportSemanticsJson(root)
    check j == "[]"

  test "exportSemanticsJson includes role / label for annotated tree":
    activeProvider = nil
    let tree = semantics(child = text("Save"),
                        role = srButton,
                        label = "Save document",
                        actions = {saTap})
    let root = mountElement(nil, tree, 0)
    let j = exportSemanticsJson(root)
    check j.contains("\"role\":\"button\"")
    check j.contains("\"label\":\"Save document\"")
    check j.contains("\"actions\":[\"tap\"]")

  test "registerSemanticsProvider overrides default":
    var providerCalled = false
    registerSemanticsProvider(proc(root: Element): string =
      providerCalled = true
      "{\"injected\": true}")
    let root = mountElement(nil, text("x"), 0)
    let j = exportSemanticsJson(root)
    check providerCalled
    check j == "{\"injected\": true}"
    activeProvider = nil

  test "defaultProvider matches exportSemanticsJsonInternal":
    let tree = semantics(child = text("ok"), role = srButton, label = "ok")
    let root = mountElement(nil, tree, 0)
    check defaultProvider(root) == exportSemanticsJsonInternal(root)
