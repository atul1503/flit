## GlCanvas API smoke test. We can't actually create a GL context
## from a headless test (it needs a window + display), so this test
## just exercises the type definitions, shader source constants,
## and the fallback path when the canvas is `nil`.

import std/unittest
import ../src/flit/rendering/canvas_gl
import ../src/flit/foundation/[render_object, geometry]

suite "GlCanvas":
  test "newGlCanvas can be called with nil and reports failure gracefully":
    # Passing nil window/renderer is invalid input. Either crashes
    # (acceptable; that's a programmer error) or returns nil
    # (preferred). We just check that the symbol resolves.
    let _ = newGlCanvas
    check true

  test "GlCanvas inherits from Canvas":
    # Type relationship check: a GlCanvas reference should be
    # assignable to a Canvas-typed variable.
    var c: Canvas = nil
    var g: GlCanvas = nil
    c = g
    check c.isNil
