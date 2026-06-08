## Tiny probe: render a box at (100, 100, 80x40) plus the same text at
## (100, 100) with two translate strategies. Save and inspect to find out
## where pixie places text.

import pixie

let img = newImage(400, 200)
let ctx = newContext(img)
ctx.fillStyle = rgba(255, 255, 255, 255)
ctx.fillRect(rect(0.0'f32, 0.0'f32, 400.0'f32, 200.0'f32))

# Reference box at (100, 100, 200x40)
ctx.fillStyle = rgba(200, 200, 255, 255)
ctx.fillRect(rect(100.0'f32, 100.0'f32, 200.0'f32, 40.0'f32))

let font = readFont("/System/Library/Fonts/Supplemental/Arial.ttf")
font.size = 16
font.paints = @[newPaint(SolidPaint)]
font.paints[0].color = rgba(255, 0, 0, 255).color  # red text

# Strategy A: translate to top-left of the rect (no fontSize offset)
img.fillText(font, "TOP-LEFT (no offset)", translate(vec2(100, 100)))

# Strategy B: translate to top + fontSize (baseline)
font.paints[0].color = rgba(0, 0, 255, 255).color
img.fillText(font, "PLUS fontSize", translate(vec2(100, 140)))

img.writeFile("/tmp/probe_text.png")
echo "wrote /tmp/probe_text.png"
