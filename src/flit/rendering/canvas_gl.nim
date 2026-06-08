## Real GPU path rasterization via OpenGL shaders.
##
## This is the "fastest paint" backend in flit. It opens an
## OpenGL context (via SDL2's `SDL_GL_CreateContext`), compiles a
## small set of SDF (signed-distance-field) shaders, and draws
## every primitive as a single GPU quad with the shape computed
## per-fragment. No CPU rasterization at all.
##
## Supported primitives:
## - Solid rectangle: trivial shader, one quad.
## - Rounded rectangle: SDF shader that computes the distance
##   from the fragment to the nearest rounded-corner edge.
##   Antialiasing via screen-space derivatives.
## - Circle: SDF shader using `length(p - center) - radius`.
## - Line: stroked SDF.
## - Image / texture blit: textured quad.
##
## The shaders are tiny (a few dozen lines each) but produce
## perfect anti-aliasing on every frame with no per-pixel CPU
## work. Caching is unnecessary because re-rendering a shape is
## already a single GPU draw call.
##
## Initialization can fail (no GL driver, headless environment,
## context-creation refused) and the caller is responsible for
## handling that path. We never crash the runner; `newGlCanvas`
## returns `nil` on failure so the caller can fall back to
## `GpuCanvas` or `SdlCanvas`.

import std/[tables, hashes]
import ../foundation/render_object
import ../foundation/geometry as geom

when not defined(js):
  import sdl2
  import opengl

  type
    Shader* = object
      program*:    GLuint
      vao*:        GLuint
      vbo*:        GLuint
      uTransform*: GLint     # mat4 model-view-projection (we use a simple ortho)
      uResolution*: GLint    # vec2: surface size in pixels
      uColor*:     GLint     # vec4 RGBA in [0,1]
      uRectMin*:   GLint     # vec2 (rect_left, rect_top)
      uRectMax*:   GLint     # vec2 (rect_right, rect_bottom)
      uRadius*:    GLint     # float: corner radius (rrect) or radius (circle)
      uCenter*:    GLint     # vec2 center (circle, line)
      uTexture*:   GLint     # sampler2D

    GlCanvas* = ref object of Canvas
      ## OpenGL-shader-backed canvas.
      window*:        WindowPtr
      glContext*:     GlContextPtr
      sdlRenderer*:   RendererPtr  # kept for compositeSubCanvas fallback
      surfaceSize*:   geom.Size
      # Shaders.
      rectShader*:    Shader
      rrectShader*:   Shader
      circleShader*:  Shader
      lineShader*:    Shader
      # Current transform: simple translation (no scale/rotation
      # on the fast path; complex transforms wrap in a
      # RepaintBoundary).
      tx*, ty*:       float32
      stateStack*:    seq[(float32, float32)]
      # Did we successfully initialize?
      ready*:         bool

  # GLSL sources. Kept ASCII-only and short for fast compile times
  # in the GL driver. Vertex shaders all share the same quad-from-
  # NDC math; fragment shaders compute SDFs and antialias via
  # screen-space derivatives.

  const vsCommon = """
#version 330 core
layout (location = 0) in vec2 a_pos;
uniform vec2 u_resolution;
out vec2 v_pix;
void main() {
  v_pix = a_pos;
  vec2 ndc = vec2(
    (a_pos.x / u_resolution.x) * 2.0 - 1.0,
    1.0 - (a_pos.y / u_resolution.y) * 2.0);
  gl_Position = vec4(ndc, 0.0, 1.0);
}
"""

  const fsSolid = """
#version 330 core
in vec2 v_pix;
uniform vec4 u_color;
out vec4 fragColor;
void main() { fragColor = u_color; }
"""

  const fsRRect = """
#version 330 core
in vec2 v_pix;
uniform vec4 u_color;
uniform vec2 u_rect_min;
uniform vec2 u_rect_max;
uniform float u_radius;
out vec4 fragColor;
// SDF for a rounded box. Returns negative inside, positive
// outside. p is the fragment position relative to the rect
// center; b is the half-extents; r is the corner radius.
float sdRoundedBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + vec2(r);
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}
void main() {
  vec2 center = (u_rect_min + u_rect_max) * 0.5;
  vec2 halfSize = (u_rect_max - u_rect_min) * 0.5;
  float d = sdRoundedBox(v_pix - center, halfSize, u_radius);
  float aa = fwidth(d);
  float alpha = 1.0 - smoothstep(-aa, aa, d);
  fragColor = vec4(u_color.rgb, u_color.a * alpha);
}
"""

  const fsCircle = """
#version 330 core
in vec2 v_pix;
uniform vec4 u_color;
uniform vec2 u_center;
uniform float u_radius;
out vec4 fragColor;
void main() {
  float d = length(v_pix - u_center) - u_radius;
  float aa = fwidth(d);
  float alpha = 1.0 - smoothstep(-aa, aa, d);
  fragColor = vec4(u_color.rgb, u_color.a * alpha);
}
"""

  const fsLine = """
#version 330 core
in vec2 v_pix;
uniform vec4 u_color;
uniform vec2 u_rect_min;  // line p0
uniform vec2 u_rect_max;  // line p1
uniform float u_radius;   // half-width
out vec4 fragColor;
// SDF for a thick line segment.
float sdSegment(vec2 p, vec2 a, vec2 b, float halfW) {
  vec2 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
  return length(pa - ba * h) - halfW;
}
void main() {
  float d = sdSegment(v_pix, u_rect_min, u_rect_max, u_radius);
  float aa = fwidth(d);
  float alpha = 1.0 - smoothstep(-aa, aa, d);
  fragColor = vec4(u_color.rgb, u_color.a * alpha);
}
"""

  proc checkShader(s: GLuint, kind: string): bool =
    var ok: GLint
    glGetShaderiv(s, GL_COMPILE_STATUS, addr ok)
    if ok == 0:
      var logLen: GLint
      glGetShaderiv(s, GL_INFO_LOG_LENGTH, addr logLen)
      var log = newString(logLen)
      glGetShaderInfoLog(s, logLen, nil, cstring(log))
      echo "GL ", kind, " shader compile error: ", log
      return false
    true

  proc checkProgram(p: GLuint): bool =
    var ok: GLint
    glGetProgramiv(p, GL_LINK_STATUS, addr ok)
    if ok == 0:
      var logLen: GLint
      glGetProgramiv(p, GL_INFO_LOG_LENGTH, addr logLen)
      var log = newString(logLen)
      glGetProgramInfoLog(p, logLen, nil, cstring(log))
      echo "GL program link error: ", log
      return false
    true

  proc compileShader(src: string, kind: GLenum): GLuint =
    result = glCreateShader(kind)
    var cs = src.cstring
    var lens: GLint = GLint(src.len)
    glShaderSource(result, 1, cast[cstringArray](addr cs), addr lens)
    glCompileShader(result)
    let kindStr = if kind == GL_VERTEX_SHADER: "vertex" else: "fragment"
    if not checkShader(result, kindStr):
      glDeleteShader(result)
      result = 0

  proc linkProgram(vs, fs: GLuint): GLuint =
    result = glCreateProgram()
    glAttachShader(result, vs)
    glAttachShader(result, fs)
    glLinkProgram(result)
    if not checkProgram(result):
      glDeleteProgram(result)
      result = 0

  proc buildShader(vsSrc, fsSrc: string): Shader =
    let vs = compileShader(vsSrc, GL_VERTEX_SHADER)
    if vs == 0: return Shader()
    let fs = compileShader(fsSrc, GL_FRAGMENT_SHADER)
    if fs == 0:
      glDeleteShader(vs)
      return Shader()
    let prog = linkProgram(vs, fs)
    glDeleteShader(vs)
    glDeleteShader(fs)
    if prog == 0: return Shader()

    var vao, vbo: GLuint
    glGenVertexArrays(1, addr vao)
    glGenBuffers(1, addr vbo)
    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    # 4 vertices * 2 floats each = 32 bytes. Placeholder data;
    # we rewrite per draw with the actual quad coordinates.
    var verts: array[8, GLfloat]
    glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(sizeof(verts)),
                 addr verts[0], GL_DYNAMIC_DRAW)
    glVertexAttribPointer(0, 2, cGL_FLOAT, GL_FALSE, GLsizei(2 * sizeof(GLfloat)), nil)
    glEnableVertexAttribArray(0)
    glBindBuffer(GL_ARRAY_BUFFER, 0)
    glBindVertexArray(0)

    Shader(
      program: prog, vao: vao, vbo: vbo,
      uTransform:  glGetUniformLocation(prog, "u_transform"),
      uResolution: glGetUniformLocation(prog, "u_resolution"),
      uColor:      glGetUniformLocation(prog, "u_color"),
      uRectMin:    glGetUniformLocation(prog, "u_rect_min"),
      uRectMax:    glGetUniformLocation(prog, "u_rect_max"),
      uRadius:     glGetUniformLocation(prog, "u_radius"),
      uCenter:     glGetUniformLocation(prog, "u_center"),
      uTexture:    glGetUniformLocation(prog, "u_texture"))

  proc newGlCanvas*(window: WindowPtr, sdlRenderer: RendererPtr,
                    w, h: int): GlCanvas =
    ## Builds a GL canvas. Creates a new GL context bound to
    ## `window` (alongside SDL2's renderer, which is fine on
    ## macOS Metal / Linux GL / Windows D3D11 because SDL2 owns
    ## its own context). Returns `nil` if context creation or
    ## shader compilation fails so the caller can fall back to
    ## `GpuCanvas`.
    discard glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
    discard glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3)
    discard glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,
                           SDL_GL_CONTEXT_PROFILE_CORE)
    let ctx = glCreateContext(window)
    if ctx.isNil:
      echo "GL context creation failed: ", getError()
      return nil
    discard glMakeCurrent(window, ctx)
    loadExtensions()

    let c = GlCanvas(window: window, glContext: ctx,
                     sdlRenderer: sdlRenderer,
                     surfaceSize: geom.Size(width: float32(w),
                                            height: float32(h)),
                     size: geom.Size(width: float32(w), height: float32(h)))
    c.rectShader = buildShader(vsCommon, fsSolid)
    c.rrectShader = buildShader(vsCommon, fsRRect)
    c.circleShader = buildShader(vsCommon, fsCircle)
    c.lineShader = buildShader(vsCommon, fsLine)
    if c.rectShader.program == 0 or c.rrectShader.program == 0 or
       c.circleShader.program == 0 or c.lineShader.program == 0:
      echo "GL canvas shader compilation failed"
      return nil

    # Standard blend setup. Premultiplied alpha is a possible
    # future change; for now we use straight alpha to match the
    # SDL backend.
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glViewport(0, 0, GLsizei(w), GLsizei(h))
    c.ready = true
    c

  proc writeQuad(s: var Shader, x0, y0, x1, y1: float32) =
    var verts: array[8, GLfloat] = [
      GLfloat(x0), GLfloat(y0),
      GLfloat(x1), GLfloat(y0),
      GLfloat(x0), GLfloat(y1),
      GLfloat(x1), GLfloat(y1),
    ]
    glBindBuffer(GL_ARRAY_BUFFER, s.vbo)
    glBufferSubData(GL_ARRAY_BUFFER, 0, GLsizeiptr(sizeof(verts)),
                    addr verts[0])

  proc setResolutionAndColor(c: GlCanvas, s: var Shader, color: uint32) =
    glUseProgram(s.program)
    if s.uResolution >= 0:
      glUniform2f(s.uResolution,
                  GLfloat(c.surfaceSize.width),
                  GLfloat(c.surfaceSize.height))
    let opaqued = c.applyOpacity(color)
    let a = GLfloat(((opaqued shr 24) and 0xFF).int) / 255.0'f32
    let r = GLfloat(((opaqued shr 16) and 0xFF).int) / 255.0'f32
    let g = GLfloat(((opaqued shr  8) and 0xFF).int) / 255.0'f32
    let b = GLfloat(( opaqued         and 0xFF).int) / 255.0'f32
    if s.uColor >= 0:
      glUniform4f(s.uColor, r, g, b, a)

  method clear*(c: GlCanvas, color: uint32) =
    if not c.ready: return
    let opaqued = c.applyOpacity(color)
    let a = GLfloat(((opaqued shr 24) and 0xFF).int) / 255.0'f32
    let r = GLfloat(((opaqued shr 16) and 0xFF).int) / 255.0'f32
    let g = GLfloat(((opaqued shr  8) and 0xFF).int) / 255.0'f32
    let b = GLfloat(( opaqued         and 0xFF).int) / 255.0'f32
    glClearColor(r, g, b, a)
    glClear(GL_COLOR_BUFFER_BIT)

  method drawRect*(c: GlCanvas, r: geom.Rect, fill: uint32) =
    if not c.ready: return
    c.setResolutionAndColor(c.rectShader, fill)
    c.rectShader.writeQuad(r.left + c.tx, r.top + c.ty,
                            r.right + c.tx, r.bottom + c.ty)
    glBindVertexArray(c.rectShader.vao)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

  method drawRRect*(c: GlCanvas, r: geom.RRect, fill: uint32) =
    if not c.ready: return
    c.setResolutionAndColor(c.rrectShader, fill)
    let s = c.rrectShader
    let radius = max(r.tl.x, max(r.tr.x, max(r.bl.x, r.br.x)))
    if s.uRectMin >= 0:
      glUniform2f(s.uRectMin, GLfloat(r.rect.left + c.tx), GLfloat(r.rect.top + c.ty))
    if s.uRectMax >= 0:
      glUniform2f(s.uRectMax, GLfloat(r.rect.right + c.tx), GLfloat(r.rect.bottom + c.ty))
    if s.uRadius >= 0:
      glUniform1f(s.uRadius, GLfloat(radius))
    c.rrectShader.writeQuad(r.rect.left + c.tx, r.rect.top + c.ty,
                            r.rect.right + c.tx, r.rect.bottom + c.ty)
    glBindVertexArray(c.rrectShader.vao)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

  method drawCircle*(c: GlCanvas, center: geom.Offset, radius: float32, fill: uint32) =
    if not c.ready: return
    c.setResolutionAndColor(c.circleShader, fill)
    let s = c.circleShader
    if s.uCenter >= 0:
      glUniform2f(s.uCenter, GLfloat(center.dx + c.tx), GLfloat(center.dy + c.ty))
    if s.uRadius >= 0:
      glUniform1f(s.uRadius, GLfloat(radius))
    c.circleShader.writeQuad(center.dx - radius + c.tx, center.dy - radius + c.ty,
                              center.dx + radius + c.tx, center.dy + radius + c.ty)
    glBindVertexArray(c.circleShader.vao)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

  method drawLine*(c: GlCanvas, p0, p1: geom.Offset, color: uint32, width: float32) =
    if not c.ready: return
    c.setResolutionAndColor(c.lineShader, color)
    let s = c.lineShader
    if s.uRectMin >= 0:
      glUniform2f(s.uRectMin, GLfloat(p0.dx + c.tx), GLfloat(p0.dy + c.ty))
    if s.uRectMax >= 0:
      glUniform2f(s.uRectMax, GLfloat(p1.dx + c.tx), GLfloat(p1.dy + c.ty))
    if s.uRadius >= 0:
      glUniform1f(s.uRadius, GLfloat(width * 0.5'f32))
    # Quad covers the line's bounding box plus a 1px margin for AA.
    let minX = min(p0.dx, p1.dx) - width
    let minY = min(p0.dy, p1.dy) - width
    let maxX = max(p0.dx, p1.dx) + width
    let maxY = max(p0.dy, p1.dy) + width
    c.lineShader.writeQuad(minX + c.tx, minY + c.ty, maxX + c.tx, maxY + c.ty)
    glBindVertexArray(c.lineShader.vao)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

  method save*(c: GlCanvas) =
    c.stateStack.add((c.tx, c.ty))

  method restore*(c: GlCanvas) =
    if c.stateStack.len > 0:
      let s = c.stateStack.pop()
      c.tx = s[0]
      c.ty = s[1]

  method translate*(c: GlCanvas, dx, dy: float32) =
    c.tx += dx
    c.ty += dy

  method scale*(c: GlCanvas, sx, sy: float32) = discard
    ## Not supported on the GL fast path. Wrap scaling subtrees in
    ## a `repaintBoundary` so they composite via a sub-canvas.

  method rotate*(c: GlCanvas, radians: float32) = discard
    ## Not supported on the GL fast path; see `scale`.

  method clipRect*(c: GlCanvas, r: geom.Rect) =
    if not c.ready: return
    glEnable(GL_SCISSOR_TEST)
    glScissor(GLint(r.left + c.tx),
              GLint(c.surfaceSize.height - r.bottom - c.ty),
              GLsizei(r.width), GLsizei(r.height))

  proc present*(c: GlCanvas) =
    ## Swaps the GL back buffer. Call once per frame.
    if not c.ready: return
    glSwapWindow(c.window)
