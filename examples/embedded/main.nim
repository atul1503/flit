## Embedded / framebuffer example. Compile with:
##   nim c -d:release -d:flitEmbedded -o:bin/embedded examples/embedded/main.nim
##
## On a Linux kiosk, the binary's `flush` callback writes ARGB
## pixels to /dev/fb0 (or wherever your hardware framebuffer
## lives). Here we stub the flush to discard pixels so the
## example compiles and runs on a regular dev machine; the
## widget tree still mounts and the frame loop ticks.

import ../../src/flit

when not defined(flitEmbedded):
  {.error: "compile this example with -d:flitEmbedded".}

type
  EmbeddedDemo = ref object of StatelessWidget

method widgetTypeName(w: EmbeddedDemo): string = "EmbeddedDemo"
method createElement(w: EmbeddedDemo): Element = newElement(ekStateless, w)
method build(w: EmbeddedDemo, ctx: BuildContext): Widget =
  container(
    padding = edgeInsetsAll(20),
    hasColor = true, color = colorBlack,
    child = center(child = column(mainAxisAlignment = maCenter, children = @[
      Widget(text("flit on a framebuffer",
        style = textStyle(color = colorWhite, fontSize = 28))),
      sizedBox(height = 12),
      text("ARGB pixels go out via the flush callback.",
        style = textStyle(color = rgb(200, 200, 200), fontSize = 14)),
    ])))

# Stub flush: drop pixels. Replace with a write to /dev/fb0 in
# real deployments.
proc dropPixels(pixels: ptr UncheckedArray[uint32], w, h: int) =
  discard

when isMainModule:
  runApp(EmbeddedDemo(), width = 800, height = 480, flush = dropPixels,
         frameRateHz = 30)
