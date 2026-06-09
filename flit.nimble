# Package

version       = "0.9.2"
author        = "Atul Tripathi"
description   = "Flit: a Flutter-inspired cross-platform UI toolkit for Nim. Declarative widgets, hot reload, single codebase for desktop, mobile, web, and embedded."
license       = "BSD-3-Clause"
srcDir        = "src"
installExt    = @["nim"]
bin           = @[]
binDir        = ""
namedBin      = {"flit_cli": "../cli/src/flit_cli"}.toTable()

# Dependencies

requires "nim >= 2.0.0"
requires "sdl2 >= 2.0.4"
requires "pixie >= 5.0.6"
requires "chroma >= 0.2.7"
requires "vmath >= 2.0.0"
requires "opengl >= 1.2.0"

task examples, "Build all example apps":
  exec "nim c -d:release -o:bin/counter examples/counter/main.nim"
  exec "nim c -d:release -o:bin/gallery examples/gallery/main.nim"
  exec "nim c -d:release -o:bin/todo examples/todo/main.nim"
  exec "nim c -d:release -o:bin/calculator examples/calculator/main.nim"
  exec "nim c -d:release -o:bin/showcase examples/showcase/main.nim"
  exec "nim c -d:release -o:bin/notes examples/notes/main.nim"

task web, "Build for web (JS backend)":
  exec "nim js -d:release -o:web/app.js examples/counter/web.nim"

task docs, "Generate API docs (open docs/api/index.html in your browser)":
  exec "nim doc --project --index:on --outdir:docs/api src/flit.nim"
  # nim doc emits flit.html and theindex.html but not index.html; the
  # curated landing page lives in docs/api/index.html and is committed
  # to the repo. If it was removed (e.g. rm -rf docs/api), fall back
  # to redirecting to the umbrella module page so the URL still loads.
  if not fileExists("docs/api/index.html"):
    writeFile("docs/api/index.html",
      "<!doctype html><meta http-equiv=refresh content=\"0; url=./flit.html\">")
  echo ""
  echo "Docs generated. Open:"
  echo "  docs/api/index.html   (curated landing page)"
  echo "  docs/api/flit.html    (umbrella module reference)"
  echo "  docs/api/theindex.html (alphabetical symbol index)"

task test, "Run test suite":
  exec "nim c -r tests/test_widgets.nim"
  exec "nim c -r tests/test_layout.nim"
  exec "nim c -r tests/test_state.nim"
  exec "nim c -r tests/test_painting.nim"
  exec "nim c -r tests/test_gestures.nim"
  exec "nim c -r tests/test_animation.nim"
  exec "nim c -r tests/test_lifecycle.nim"
  exec "nim c -r tests/test_container.nim"
  exec "nim c -r tests/test_opacity.nim"
  exec "nim c -r tests/test_audit.nim"
  exec "nim c -r tests/test_property_foundation.nim"
  exec "nim c -r tests/test_property_layout.nim"
  exec "nim c -r tests/test_property_reconcile.nim"
  exec "nim c -r tests/test_flutter_conformance.nim"
  exec "nim c -r tests/test_material_cupertino.nim"
  exec "nim c -r tests/test_widgets_extra.nim"
  exec "nim c -r tests/test_listenable.nim"
  exec "nim c -r tests/test_inherited.nim"
  exec "nim c -r tests/test_layer.nim"
  exec "nim c -r tests/test_repaint_boundary.nim"
  exec "nim c -r tests/test_lazy_list.nim"
  exec "nim c -r tests/test_harfbuzz.nim"
  exec "nim c -r tests/test_glyph_atlas_harfbuzz.nim"
  exec "nim c -r tests/test_canvas_gl.nim"
  exec "nim c -r tests/test_raster_pool.nim"
  exec "nim c -r tests/test_identity_shortcircuit.nim"
  exec "nim c -r tests/test_focus.nim"
  exec "nim c -r tests/test_text_field.nim"
  exec "nim c -r tests/test_navigator.nim"
  exec "nim c -r tests/test_form.nim"
  exec "nim c -r tests/test_directionality.nim"
  exec "nim c -r tests/test_image.nim"

task fmt, "Format code with nimpretty":
  exec "find src tests examples -name '*.nim' -exec nimpretty {} \\;"
