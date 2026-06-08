# Package

version       = "0.2.0"
author        = "Aman Tripathi"
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

task examples, "Build all example apps":
  exec "nim c -d:release -o:bin/counter examples/counter/main.nim"
  exec "nim c -d:release -o:bin/gallery examples/gallery/main.nim"
  exec "nim c -d:release -o:bin/todo examples/todo/main.nim"
  exec "nim c -d:release -o:bin/calculator examples/calculator/main.nim"
  exec "nim c -d:release -o:bin/showcase examples/showcase/main.nim"

task web, "Build for web (JS backend)":
  exec "nim js -d:release -o:web/app.js examples/counter/web.nim"

task docs, "Generate API docs":
  exec "nim doc --project --index:on --outdir:docs/api src/flit.nim"

task test, "Run test suite":
  exec "nim c -r tests/test_widgets.nim"
  exec "nim c -r tests/test_layout.nim"
  exec "nim c -r tests/test_state.nim"
  exec "nim c -r tests/test_painting.nim"

task fmt, "Format code with nimpretty":
  exec "find src tests examples -name '*.nim' -exec nimpretty {} \\;"
