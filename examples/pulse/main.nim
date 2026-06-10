## Pulse: an animation-heavy music-player-style demo. Stress-tests
## the animation system through the public API only:
##
## - Splash screen with fade + scale entrance, auto-navigates
## - Pulsing circular play button (repeat animation)
## - Rotating album art while "playing"
## - 12-bar animated equalizer (each bar on its own controller
##   with a phase-offset duration so they desync naturally)
## - Animated playback progress bar with time labels
## - Like button with bounce-out pop on toggle
## - Animated tab indicator that slides between 3 tabs
## - Volume slider with eased thumb
## - Track list with per-row entrance animation and navigation to
##   the now-playing screen with a slide transition
##
## All fake data. Run:
##   nim c -r examples/pulse/main.nim

import std/[strutils, math, sequtils]
import ../../src/flit
import ../../src/flit/widgets/navigator as navw

# Palette: dark player aesthetic.
let bgDark      = rgb(18, 18, 24)
let bgCard      = rgb(28, 28, 38)
let accent      = rgb(98, 0, 238)       # purple
let accentHot   = rgb(187, 134, 252)    # light purple
let accentTeal  = rgb(3, 218, 198)
let textHi      = rgb(245, 245, 250)
let textLo      = rgb(160, 160, 175)
let barColors = @[
  rgb(187, 134, 252), rgb(3, 218, 198), rgb(255, 105, 97),
  rgb(255, 180, 0), rgb(0, 200, 83), rgb(41, 182, 246)]

# Fake catalog.

type
  Track = ref object
    id:       int
    title:    string
    artist:   string
    duration: int       # seconds
    hue:      Color     # album art color

let tracks = @[
  Track(id: 1, title: "Midnight Drive",   artist: "Neon Harbor",    duration: 214, hue: rgb(98, 0, 238)),
  Track(id: 2, title: "Glass Waves",      artist: "Aurora Fields",  duration: 187, hue: rgb(3, 168, 244)),
  Track(id: 3, title: "Low Orbit",        artist: "Satellite Park", duration: 243, hue: rgb(0, 200, 130)),
  Track(id: 4, title: "Paper Lanterns",   artist: "Kyoto Drift",    duration: 198, hue: rgb(255, 110, 64)),
  Track(id: 5, title: "Static Bloom",     artist: "Velvet Static",  duration: 226, hue: rgb(213, 0, 110)),
  Track(id: 6, title: "Citrus Sky",       artist: "Marmalade Sun",  duration: 175, hue: rgb(255, 179, 0)),
  Track(id: 7, title: "Ferrofluid",       artist: "Magnet Theory",  duration: 251, hue: rgb(84, 110, 255)),
  Track(id: 8, title: "Slow Lightning",   artist: "Cloud Atlas Co", duration: 207, hue: rgb(0, 188, 212)),
]

proc fmtTime(secs: int): string =
  let m = secs div 60
  let s = secs mod 60
  $m & ":" & (if s < 10: "0" & $s else: $s)

# Shared player state.
let currentTrack = newValueNotifier[int](1)     # track id
let isPlaying    = newValueNotifier[bool](false)
let likedTracks  = newValueNotifier[seq[int]](@[])

proc trackById(id: int): Track =
  for t in tracks:
    if t.id == id: return t
  tracks[0]

proc isLiked(id: int): bool =
  for x in likedTracks.value:
    if x == id: return true
  false

proc toggleLike(id: int) =
  var keep: seq[int]
  var found = false
  for x in likedTracks.value:
    if x == id: found = true
    else: keep.add(x)
  if not found: keep.add(id)
  likedTracks.value = keep

# Forward decls.
proc homeScreen*(): Widget
proc nowPlayingScreen*(trackId: int): Widget

# ---------------------------------------------------------------
# Animated widgets
# ---------------------------------------------------------------

# Pulsing ring: a circle that scales 1.0 -> 1.25 -> 1.0 forever.
type
  PulsingPlay = ref object of StatefulWidget
    size: float32
  PulsingPlayState = ref object of State
    ctrl: AnimationController

method widgetTypeName(w: PulsingPlay): string = "PulsingPlay"
method createElement(w: PulsingPlay): Element = newElement(ekStateful, w)
method createState(w: PulsingPlay): State = PulsingPlayState()

method initState(s: PulsingPlayState) =
  s.ctrl = newAnimationController(durationSec = 0.9)
  s.ctrl.addListener(proc(v: float32) = setState(s, proc() = discard))
  if not globalBinding.isNil:
    s.ctrl.repeat(globalBinding, curve = curveEaseInOut, reverse = true)

method dispose(s: PulsingPlayState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: PulsingPlayState, ctx: BuildContext): Widget =
  let host = PulsingPlay(s.element.widget)
  let scaleVal = 1.0'f32 + 0.18'f32 * s.ctrl.value
  let halo = 0.35'f32 * (1.0'f32 - s.ctrl.value)
  listenableBuilder(isPlaying, proc(ctx: BuildContext, playing: bool): Widget =
    gestureDetector(behavior = htOpaque,
      onTap = proc() = isPlaying.value = not isPlaying.value,
      child = stack(alignment = alignCenter, children = @[
        # Halo ring fades out as it expands.
        Widget(transform(scale = scaleVal * 1.25'f32,
          child = container(
            width = host.size, height = host.size,
            hasDecoration = true,
            decoration = boxDecoration(
              color = rgba(187, 134, 252, uint8(halo * 255)),
              borderRadius = host.size / 2)))),
        transform(scale = scaleVal,
          child = container(
            width = host.size, height = host.size,
            hasDecoration = true,
            decoration = boxDecoration(color = accent,
              borderRadius = host.size / 2),
            child = center(child = icon(
              if playing: "minus" else: "chevron.right",
              size = host.size * 0.4'f32, color = colorWhite)))),
      ])))

proc pulsingPlay(size: float32 = 72): PulsingPlay =
  PulsingPlay(size: size)

# Rotating album art: spins while isPlaying, eases to a stop when
# paused.
type
  SpinningArt = ref object of StatefulWidget
    color: Color
    size: float32
  SpinningArtState = ref object of State
    ctrl: AnimationController
    angle: float32

method widgetTypeName(w: SpinningArt): string = "SpinningArt"
method createElement(w: SpinningArt): Element = newElement(ekStateful, w)
method createState(w: SpinningArt): State = SpinningArtState()

method initState(s: SpinningArtState) =
  s.ctrl = newAnimationController(durationSec = 4.0)
  s.ctrl.addListener(proc(v: float32) =
    # Accumulate rotation only while playing.
    if isPlaying.value:
      s.angle += 0.025'f32
      if s.angle > 2 * PI: s.angle -= 2 * PI
    setState(s, proc() = discard))
  if not globalBinding.isNil:
    s.ctrl.repeat(globalBinding)

method dispose(s: SpinningArtState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: SpinningArtState, ctx: BuildContext): Widget =
  let host = SpinningArt(s.element.widget)
  transform(rotation = s.angle,
    child = container(
      width = host.size, height = host.size,
      hasDecoration = true,
      decoration = boxDecoration(color = host.color,
        borderRadius = host.size / 2),
      child = center(child = container(
        width = host.size * 0.25'f32, height = host.size * 0.25'f32,
        hasDecoration = true,
        decoration = boxDecoration(color = bgDark,
          borderRadius = host.size * 0.125'f32)))))

proc spinningArt(color: Color, size: float32 = 220): SpinningArt =
  SpinningArt(color: color, size: size)

# Equalizer: 12 bars, each with its own controller at a slightly
# different duration so they fall out of phase.
type
  Equalizer = ref object of StatefulWidget
    barCount: int
    height: float32
  EqualizerState = ref object of State
    ctrls: seq[AnimationController]

method widgetTypeName(w: Equalizer): string = "Equalizer"
method createElement(w: Equalizer): Element = newElement(ekStateful, w)
method createState(w: Equalizer): State = EqualizerState()

method initState(s: EqualizerState) =
  let host = Equalizer(s.element.widget)
  for i in 0 ..< host.barCount:
    # Durations 0.35s .. 0.85s so bars desync.
    let dur = 0.35'f32 + 0.5'f32 * (float32(i mod 5) / 4.0'f32)
    let c = newAnimationController(durationSec = dur)
    c.addListener(proc(v: float32) = setState(s, proc() = discard))
    if not globalBinding.isNil:
      c.repeat(globalBinding, curve = curveEaseInOut, reverse = true)
    s.ctrls.add(c)

method dispose(s: EqualizerState) =
  for c in s.ctrls:
    if not c.isNil: c.dispose()

method build(s: EqualizerState, ctx: BuildContext): Widget =
  let host = Equalizer(s.element.widget)
  listenableBuilder(isPlaying, proc(ctx: BuildContext, playing: bool): Widget =
    var bars: seq[Widget]
    for i in 0 ..< host.barCount:
      let v = if playing and i < s.ctrls.len: s.ctrls[i].value else: 0.12'f32
      let barH = max(6.0'f32, host.height * v)
      bars.add(padding(padding = edgeInsetsSymmetric(horizontal = 3, vertical = 0),
        child = column(mainAxisAlignment = maEnd, mainAxisSize = msMax,
                       children = @[
          Widget(container(
            width = 8, height = barH,
            hasDecoration = true,
            decoration = boxDecoration(
              color = barColors[i mod barColors.len],
              borderRadius = 4))),
        ])))
    container(height = host.height,
      child = row(crossAxisAlignment = caEnd, mainAxisAlignment = maCenter,
                  children = bars)))

proc equalizer(barCount: int = 12, height: float32 = 80): Equalizer =
  Equalizer(barCount: barCount, height: height)

# Progress bar: a controller runs the length of the track; the
# fill width and the elapsed label both derive from its value.
type
  ProgressBar = ref object of StatefulWidget
    duration: int
  ProgressBarState = ref object of State
    ctrl: AnimationController

method widgetTypeName(w: ProgressBar): string = "ProgressBar"
method createElement(w: ProgressBar): Element = newElement(ekStateful, w)
method createState(w: ProgressBar): State = ProgressBarState()

method initState(s: ProgressBarState) =
  let host = ProgressBar(s.element.widget)
  s.ctrl = newAnimationController(durationSec = float32(host.duration))
  s.ctrl.addListener(proc(v: float32) = setState(s, proc() = discard))
  if not globalBinding.isNil:
    s.ctrl.forward(globalBinding)

method dispose(s: ProgressBarState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: ProgressBarState, ctx: BuildContext): Widget =
  let host = ProgressBar(s.element.widget)
  let progress = s.ctrl.value
  let elapsed = int(float32(host.duration) * progress)
  column(crossAxisAlignment = caStretch, mainAxisSize = msMin, children = @[
    # Track + fill. Fill width animates with the controller.
    Widget(stack(children = @[
      Widget(container(height = 6,
        hasDecoration = true,
        decoration = boxDecoration(color = rgb(60, 60, 75), borderRadius = 3))),
      row(children = @[
        Widget(flexible(flex = max(1, int(progress * 1000)),
          child = container(height = 6,
            hasDecoration = true,
            decoration = boxDecoration(color = accentHot, borderRadius = 3)))),
        flexible(flex = max(1, int((1.0'f32 - progress) * 1000)),
          child = sizedBox(height = 6)),
      ]),
    ])),
    sizedBox(height = 6),
    row(mainAxisAlignment = maSpaceBetween, children = @[
      Widget(text(fmtTime(elapsed),
        style = textStyle(fontSize = 11, color = textLo))),
      text(fmtTime(host.duration),
        style = textStyle(fontSize = 11, color = textLo)),
    ]),
  ])

proc progressBar(duration: int, trackId: int = 0): ProgressBar =
  ## Key by track id so navigating to a different song mounts a
  ## FRESH state (a fresh AnimationController starting at 0).
  ## Without the key, reconciliation matches the new ProgressBar
  ## to the old element by type + position and the previous
  ## track's controller (old progress, old duration) survives.
  ProgressBar(duration: duration, key: newValueKey("progress-" & $trackId))

# Like button: pops with bounce-out when toggled on.
type
  LikeButton = ref object of StatefulWidget
    trackId: int
  LikeButtonState = ref object of State
    ctrl: AnimationController

method widgetTypeName(w: LikeButton): string = "LikeButton"
method createElement(w: LikeButton): Element = newElement(ekStateful, w)
method createState(w: LikeButton): State = LikeButtonState()

method initState(s: LikeButtonState) =
  s.ctrl = newAnimationController(durationSec = 0.45)
  s.ctrl.value = 1.0
  s.ctrl.addListener(proc(v: float32) = setState(s, proc() = discard))

method dispose(s: LikeButtonState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: LikeButtonState, ctx: BuildContext): Widget =
  let host = LikeButton(s.element.widget)
  let tid = host.trackId
  listenableBuilder(likedTracks, proc(ctx: BuildContext, ids: seq[int]): Widget =
    # Bounce: scale follows bounce-out of the controller.
    let scaleVal = 0.6'f32 + 0.4'f32 * curveBounceOut(s.ctrl.value)
    gestureDetector(behavior = htOpaque,
      onTap = proc() =
        toggleLike(tid)
        s.ctrl.value = 0
        if not globalBinding.isNil:
          s.ctrl.forward(globalBinding),
      child = transform(scale = scaleVal,
        child = icon("heart", size = 28,
          color = (if isLiked(tid): rgb(255, 82, 119) else: rgb(110, 110, 125))))))

proc likeButton(trackId: int): LikeButton =
  LikeButton(trackId: trackId)

# Animated tab bar: an indicator slides under the active tab.
type
  TabBar = ref object of StatefulWidget
    labels: seq[string]
    onChange: proc(idx: int) {.closure.}
  TabBarState = ref object of State
    ctrl: AnimationController
    fromIdx, toIdx: int

method widgetTypeName(w: TabBar): string = "TabBar"
method createElement(w: TabBar): Element = newElement(ekStateful, w)
method createState(w: TabBar): State = TabBarState()

method initState(s: TabBarState) =
  s.ctrl = newAnimationController(durationSec = 0.25)
  s.ctrl.value = 1.0
  s.ctrl.addListener(proc(v: float32) = setState(s, proc() = discard))

method dispose(s: TabBarState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: TabBarState, ctx: BuildContext): Widget =
  let host = TabBar(s.element.widget)
  let n = host.labels.len
  if n == 0: return sizedBox()
  # Indicator position interpolates fromIdx -> toIdx with ease-out.
  let t = curveEaseOut(s.ctrl.value)
  let pos = float32(s.fromIdx) + (float32(s.toIdx) - float32(s.fromIdx)) * t
  var cells: seq[Widget]
  for i in 0 ..< n:
    let idx = i
    let active = idx == s.toIdx
    cells.add(expanded(child = gestureDetector(behavior = htOpaque,
      onTap = proc() =
        if idx != s.toIdx:
          s.fromIdx = s.toIdx
          s.toIdx = idx
          s.ctrl.value = 0
          if not globalBinding.isNil:
            s.ctrl.forward(globalBinding)
          if not host.onChange.isNil: host.onChange(idx),
      # Bounded height so center() can't expand to fill the screen.
      child = container(
        height = 38,
        child = center(child = text(host.labels[i],
          style = textStyle(fontSize = 14,
            color = (if active: textHi else: textLo))))))))
  column(crossAxisAlignment = caStretch, mainAxisSize = msMin, children = @[
    Widget(row(children = cells)),
    # Sliding indicator: left spacer flex tracks `pos`.
    row(children = @[
      Widget(flexible(flex = max(1, int(pos * 1000) + 1),
        child = sizedBox(height = 3))),
      flexible(flex = 1000,
        child = container(height = 3,
          hasDecoration = true,
          decoration = boxDecoration(color = accentHot, borderRadius = 2))),
      flexible(flex = max(1, int((float32(n - 1) - pos) * 1000) + 1),
        child = sizedBox(height = 3)),
    ]),
  ])

proc tabBar(labels: seq[string], onChange: proc(idx: int) = nil): TabBar =
  TabBar(labels: labels, onChange: onChange)

# Volume slider with eased thumb.
type
  VolumeSlider = ref object of StatefulWidget
  VolumeSliderState = ref object of State
    ctrl: AnimationController
    fromV, toV: float32

method widgetTypeName(w: VolumeSlider): string = "VolumeSlider"
method createElement(w: VolumeSlider): Element = newElement(ekStateful, w)
method createState(w: VolumeSlider): State =
  VolumeSliderState(fromV: 0.7, toV: 0.7)

method initState(s: VolumeSliderState) =
  s.ctrl = newAnimationController(durationSec = 0.3)
  s.ctrl.value = 1.0
  s.ctrl.addListener(proc(v: float32) = setState(s, proc() = discard))

method dispose(s: VolumeSliderState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: VolumeSliderState, ctx: BuildContext): Widget =
  let t = curveEaseOut(s.ctrl.value)
  let vol = s.fromV + (s.toV - s.fromV) * t
  let setTo = proc(v: float32) =
    s.fromV = vol
    s.toV = clamp(v, 0.0'f32, 1.0'f32)
    s.ctrl.value = 0
    if not globalBinding.isNil: s.ctrl.forward(globalBinding)
  row(crossAxisAlignment = caCenter, children = @[
    Widget(gestureDetector(behavior = htOpaque,
      onTap = proc() = setTo(s.toV - 0.2'f32),
      child = icon("minus", size = 16, color = textLo))),
    expanded(child = padding(
      padding = edgeInsetsSymmetric(horizontal = 10, vertical = 0),
      child = stack(children = @[
        Widget(container(height = 4,
          hasDecoration = true,
          decoration = boxDecoration(color = rgb(60, 60, 75), borderRadius = 2))),
        row(children = @[
          Widget(flexible(flex = max(1, int(vol * 1000)),
            child = container(height = 4,
              hasDecoration = true,
              decoration = boxDecoration(color = accentTeal, borderRadius = 2)))),
          flexible(flex = max(1, int((1.0'f32 - vol) * 1000)),
            child = sizedBox(height = 4)),
        ]),
      ]))),
    gestureDetector(behavior = htOpaque,
      onTap = proc() = setTo(s.toV + 0.2'f32),
      child = icon("plus", size = 16, color = textLo)),
  ])

proc volumeSlider(): VolumeSlider = VolumeSlider()

# Track row with entrance animation: slides in from the right with
# a stagger based on its index.
type
  AnimatedRow = ref object of StatefulWidget
    track: Track
    index: int
  AnimatedRowState = ref object of State
    ctrl: AnimationController

method widgetTypeName(w: AnimatedRow): string = "AnimatedRow"
method createElement(w: AnimatedRow): Element = newElement(ekStateful, w)
method createState(w: AnimatedRow): State = AnimatedRowState()

method initState(s: AnimatedRowState) =
  let host = AnimatedRow(s.element.widget)
  # Stagger: row N starts after N * 60ms by stretching the duration
  # and easing late. Approximate stagger with longer durations.
  let dur = 0.3'f32 + float32(host.index) * 0.06'f32
  s.ctrl = newAnimationController(durationSec = dur)
  s.ctrl.addListener(proc(v: float32) = setState(s, proc() = discard))
  if not globalBinding.isNil:
    s.ctrl.forward(globalBinding, curve = curveEaseOut)

method dispose(s: AnimatedRowState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: AnimatedRowState, ctx: BuildContext): Widget =
  let host = AnimatedRow(s.element.widget)
  let tk = host.track
  let tid = tk.id
  let slide = (1.0'f32 - s.ctrl.value) * 80.0'f32
  transform(translation = Offset(dx: slide, dy: 0),
    child = opacity(opacity = s.ctrl.value,
      child = gestureDetector(behavior = htOpaque,
        onTap = proc() =
          currentTrack.value = tid
          isPlaying.value = true
          currentNavigator().push(proc(): Widget = nowPlayingScreen(tid),
                                  transition = trSlideUp),
        child = container(
          margin = edgeInsetsSymmetric(horizontal = 16, vertical = 5),
          padding = edgeInsetsAll(12),
          hasDecoration = true,
          decoration = boxDecoration(color = bgCard, borderRadius = 12),
          child = row(crossAxisAlignment = caCenter, children = @[
            # Mini album art.
            Widget(container(width = 46, height = 46,
              hasDecoration = true,
              decoration = boxDecoration(color = tk.hue, borderRadius = 10))),
            sizedBox(width = 12),
            expanded(child = column(crossAxisAlignment = caStart,
                                    mainAxisSize = msMin, children = @[
              Widget(text(tk.title,
                style = textStyle(fontSize = 15, color = textHi))),
              sizedBox(height = 2),
              text(tk.artist,
                style = textStyle(fontSize = 12, color = textLo)),
            ])),
            text(fmtTime(tk.duration),
              style = textStyle(fontSize = 12, color = textLo)),
            sizedBox(width = 14),
            likeButton(tid),
          ])))))

proc animatedRow(track: Track, index: int): AnimatedRow =
  AnimatedRow(track: track, index: index)

# ---------------------------------------------------------------
# Screens
# ---------------------------------------------------------------

# Splash: logo scales in with bounce, fades, then auto-navigates.
type
  SplashScreen = ref object of StatefulWidget
  SplashState = ref object of State
    ctrl: AnimationController
    navigated: bool

method widgetTypeName(w: SplashScreen): string = "SplashScreen"
method createElement(w: SplashScreen): Element = newElement(ekStateful, w)
method createState(w: SplashScreen): State = SplashState()

method initState(s: SplashState) =
  s.ctrl = newAnimationController(durationSec = 1.4)
  s.ctrl.addListener(proc(v: float32) =
    setState(s, proc() = discard)
    if v >= 1.0 and not s.navigated:
      s.navigated = true
      currentNavigator().push(proc(): Widget = homeScreen(),
                              transition = trFade))
  if not globalBinding.isNil:
    s.ctrl.forward(globalBinding)

method dispose(s: SplashState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: SplashState, ctx: BuildContext): Widget =
  # Two phases packed into one controller:
  # 0.0-0.6: logo scale-in with bounce.
  # 0.6-1.0: hold.
  let raw = s.ctrl.value
  let logoT = clamp(raw / 0.6'f32, 0.0'f32, 1.0'f32)
  let scaleVal = 0.4'f32 + 0.6'f32 * curveBounceOut(logoT)
  container(hasColor = true, color = bgDark,
    child = center(child = transform(scale = scaleVal,
      child = column(mainAxisSize = msMin, crossAxisAlignment = caCenter,
                     children = @[
        Widget(container(width = 110, height = 110,
          hasDecoration = true,
          decoration = boxDecoration(color = accent, borderRadius = 55),
          child = center(child = icon("chevron.right", size = 48,
            color = colorWhite)))),
        sizedBox(height = 18),
        text("Pulse",
          style = textStyle(fontSize = 34, color = textHi)),
        sizedBox(height = 6),
        text("music in motion",
          style = textStyle(fontSize = 14, color = textLo)),
      ]))))

# Home: tab bar + equalizer header + animated track list.
proc homeScreen*(): Widget =
  let tabIdx = newValueNotifier[int](0)
  container(hasColor = true, color = bgDark,
    child = column(crossAxisAlignment = caStretch, children = @[
      # Header.
      Widget(padding(padding = edgeInsetsAll(20),
        child = row(crossAxisAlignment = caCenter, children = @[
          Widget(column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                        children = @[
            Widget(text("Pulse",
              style = textStyle(fontSize = 26, color = textHi))),
            text("8 tracks - all systems nominal",
              style = textStyle(fontSize = 12, color = textLo)),
          ])),
          expanded(child = sizedBox(width = 0)),
          pulsingPlay(size = 52),
        ]))),
      # Equalizer strip reacts to play state.
      equalizer(barCount = 14, height = 70),
      sizedBox(height = 8),
      # Tabs.
      tabBar(@["Tracks", "Albums", "Artists"],
        onChange = proc(idx: int) = tabIdx.value = idx),
      sizedBox(height = 8),
      # Animated list.
      expanded(child = listenableBuilder(tabIdx,
        proc(ctx: BuildContext, idx: int): Widget =
          let visible =
            case idx
            of 1: tracks.filterIt(it.id mod 2 == 0)   # fake "albums"
            of 2: tracks.filterIt(it.id mod 2 == 1)   # fake "artists"
            else: tracks
          var rows: seq[Widget]
          for i, tk in visible:
            rows.add(animatedRow(tk, i))
          scrollView(child = column(crossAxisAlignment = caStretch,
                                    mainAxisSize = msMin,
                                    children = rows)))),
    ]))

# Now playing: spinning art + progress + volume + transport.
proc nowPlayingScreen*(trackId: int): Widget =
  let tk = trackById(trackId)
  container(hasColor = true, color = bgDark,
    child = column(crossAxisAlignment = caStretch, children = @[
      # Top bar with back chevron.
      Widget(padding(padding = edgeInsetsAll(16),
        child = row(crossAxisAlignment = caCenter, children = @[
          Widget(gestureDetector(behavior = htOpaque,
            onTap = proc() = currentNavigator().pop(),
            child = icon("chevron.down", size = 26, color = textHi))),
          # Bound the center's height or it expands the whole row
          # vertically (center fills bounded constraints).
          expanded(child = container(height = 28,
            child = center(child = text("Now Playing",
              style = textStyle(fontSize = 14, color = textLo))))),
          likeButton(tk.id),
        ]))),
      sizedBox(height = 12),
      # Spinning album art. center() expands to fill bounded
      # constraints, so cap each centered block with an explicit
      # height to keep the column compact.
      container(height = 240,
        child = center(child = spinningArt(tk.hue, size = 230))),
      sizedBox(height = 22),
      container(height = 30,
        child = center(child = text(tk.title,
          style = textStyle(fontSize = 22, color = textHi)))),
      sizedBox(height = 2),
      container(height = 20,
        child = center(child = text(tk.artist,
          style = textStyle(fontSize = 14, color = textLo)))),
      sizedBox(height = 22),
      # Progress.
      padding(padding = edgeInsetsSymmetric(horizontal = 28, vertical = 0),
        child = progressBar(tk.duration, trackId = tk.id)),
      sizedBox(height = 16),
      # Transport row: prev | play | next.
      container(height = 96,
        child = center(child = row(mainAxisSize = msMin, crossAxisAlignment = caCenter,
                         children = @[
        Widget(gestureDetector(behavior = htOpaque,
          onTap = proc() =
            let prevId = if tk.id <= 1: tracks[^1].id else: tk.id - 1
            currentTrack.value = prevId
            currentNavigator().pop()
            currentNavigator().push(proc(): Widget = nowPlayingScreen(prevId),
                                    transition = trSlideRight),
          child = icon("chevron.left", size = 34, color = textHi))),
        sizedBox(width = 30),
        pulsingPlay(size = 76),
        sizedBox(width = 30),
        gestureDetector(behavior = htOpaque,
          onTap = proc() =
            let nextId = if tk.id >= tracks.len: 1 else: tk.id + 1
            currentTrack.value = nextId
            currentNavigator().pop()
            currentNavigator().push(proc(): Widget = nowPlayingScreen(nextId),
                                    transition = trSlideLeft),
          child = icon("chevron.right", size = 34, color = textHi)),
      ]))),
      sizedBox(height = 22),
      # Equalizer mirrors play state here too.
      equalizer(barCount = 18, height = 56),
      sizedBox(height = 16),
      # Volume.
      padding(padding = edgeInsetsSymmetric(horizontal = 36, vertical = 0),
        child = volumeSlider()),
      sizedBox(height = 24),
    ]))

# Root.
type
  PulseApp = ref object of StatelessWidget

method widgetTypeName(w: PulseApp): string = "PulseApp"
method createElement(w: PulseApp): Element = newElement(ekStateless, w)
method build(w: PulseApp, ctx: BuildContext): Widget =
  navigator(proc(): Widget = SplashScreen())

when isMainModule:
  runApp(PulseApp())
