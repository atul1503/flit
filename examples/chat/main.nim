## Chat: the messaging-app archetype probe. Exercises the feature
## combination no other example covers: a scrollable list that
## GROWS at the bottom while the user is interacting, plus a
## persistent input bar, plus timed "incoming" events.
##
## What it stress-tests:
## - ScrollController.scrollToEnd(): stick-to-latest-message when
##   sending or receiving (the API this archetype forced us to add)
## - TextField + Enter-to-send in a bottom bar that never moves
## - Streaming inserts: a fake contact replies after a delay,
##   driven by an AnimationController used as a one-shot timer
## - Typing indicator: three dots pulsing with staggered phases
## - Message bubbles: left / right aligned, asymmetric corner
##   radii, timestamps
##
## All fake data. Run:
##   nim c -r examples/chat/main.nim

import std/[strutils, math, os]
import ../../src/flit

# Palette.
let bgChat     = rgb(17, 27, 33)        # WhatsApp-dark-ish backdrop
let bgBar      = rgb(32, 44, 51)
let bubbleMine = rgb(0, 92, 75)
let bubbleThem = rgb(32, 44, 51)
let textHi     = rgb(233, 237, 239)
let textLo     = rgb(134, 150, 160)
let accent     = rgb(0, 168, 132)

type
  Message = ref object
    mine: bool
    body: string
    time: string
    imagePath: string   # non-empty = an attached image to render

# Conversation state.
let messages = newValueNotifier[seq[Message]](@[
  Message(mine: false, body: "Hey! Did you see the launch?", time: "09:12"),
  Message(mine: true,  body: "Just now. The demo was smooth.", time: "09:13"),
  Message(mine: false, body: "The animation on the splash screen tho", time: "09:13"),
  Message(mine: true,  body: "Right? All flit, no native code.", time: "09:14"),
])
let isTyping = newValueNotifier[bool](false)

# Canned replies the fake contact cycles through.
let cannedReplies = @[
  "Nice, tell me more.",
  "Hmm, interesting take.",
  "Can you send the link?",
  "That benchmark number is wild.",
  "Same energy here.",
  "Ship it.",
]
var replyIdx = 0

let chatScroll = newScrollController()

# Dev hook: FLIT_CHAT_SEED_IMAGE=<path> appends an image message at
# startup so the image-bubble path can be verified headlessly (the
# native picker can't be driven by automated tests).
if getEnv("FLIT_CHAT_SEED_IMAGE").len > 0:
  var seeded = messages.value
  seeded.add(Message(mine: true, body: "check this out",
    time: "09:15", imagePath: getEnv("FLIT_CHAT_SEED_IMAGE")))
  messages.value = seeded

proc nowStamp(): string =
  # Fake clock that just advances by message count.
  let n = messages.value.len
  "09:" & $(14 + n)

proc sendMessage(body: string, imagePath: string = "") =
  if body.strip.len == 0 and imagePath.len == 0: return
  var list = messages.value
  list.add(Message(mine: true, body: body.strip, time: nowStamp(),
                   imagePath: imagePath))
  messages.value = list
  chatScroll.scrollToEnd()
  # Fake contact starts "typing" and replies after a delay.
  isTyping.value = true

proc attachImage(caption: string) =
  ## Opens the native file picker filtered to images. Sends the
  ## chosen file as an image message (with the current input text
  ## as its caption). The picker blocks until dismissed; cancelling
  ## returns "" and nothing is sent.
  let path = openFile(
    title = "Send an image",
    filters = @[FileFilter(name: "Images",
                           exts: @["png", "jpg", "jpeg", "bmp", "gif"])])
  if path.len > 0:
    sendMessage(caption, imagePath = path)

# Reply timer: a one-shot AnimationController. When it completes,
# the contact's reply lands and the typing indicator clears.
type
  ReplyTimer = ref object of StatefulWidget
  ReplyTimerState = ref object of State
    ctrl: AnimationController
    armed: bool

method widgetTypeName(w: ReplyTimer): string = "ReplyTimer"
method createElement(w: ReplyTimer): Element = newElement(ekStateful, w)
method createState(w: ReplyTimer): State = ReplyTimerState()

method initState(s: ReplyTimerState) =
  s.ctrl = newAnimationController(durationSec = 1.6)
  s.ctrl.addListener(proc(v: float32) =
    if v >= 1.0 and s.armed:
      s.armed = false
      isTyping.value = false
      var list = messages.value
      list.add(Message(mine: false,
        body: cannedReplies[replyIdx mod cannedReplies.len],
        time: nowStamp()))
      inc replyIdx
      messages.value = list
      chatScroll.scrollToEnd())
  # Arm whenever typing starts.
  isTyping.addListener(proc(t: bool) =
    if t and not s.armed:
      s.armed = true
      s.ctrl.value = 0
      if not globalBinding.isNil:
        s.ctrl.forward(globalBinding))

method dispose(s: ReplyTimerState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: ReplyTimerState, ctx: BuildContext): Widget =
  sizedBox()   # invisible; exists only to host the timer

# Typing indicator: three dots pulsing out of phase.
type
  TypingDots = ref object of StatefulWidget
  TypingDotsState = ref object of State
    ctrl: AnimationController

method widgetTypeName(w: TypingDots): string = "TypingDots"
method createElement(w: TypingDots): Element = newElement(ekStateful, w)
method createState(w: TypingDots): State = TypingDotsState()

method initState(s: TypingDotsState) =
  s.ctrl = newAnimationController(durationSec = 0.9)
  s.ctrl.addListener(proc(v: float32) = setState(s, proc() = discard))
  if not globalBinding.isNil:
    s.ctrl.repeat(globalBinding)

method dispose(s: TypingDotsState) =
  if not s.ctrl.isNil: s.ctrl.dispose()

method build(s: TypingDotsState, ctx: BuildContext): Widget =
  var dots: seq[Widget]
  for i in 0 ..< 3:
    # Stagger each dot's phase by a third of the cycle.
    let phase = (s.ctrl.value + float32(i) / 3.0'f32) mod 1.0'f32
    let lift = sin(phase * PI).float32 * 6.0'f32
    dots.add(padding(padding = edgeInsetsSymmetric(horizontal = 3, vertical = 0),
      child = transform(translation = Offset(dx: 0, dy: -lift),
        child = container(width = 8, height = 8,
          hasDecoration = true,
          decoration = boxDecoration(color = textLo, borderRadius = 4)))))
  container(
    padding = edgeInsetsSymmetric(horizontal = 14, vertical = 10),
    hasDecoration = true,
    decoration = boxDecoration(color = bubbleThem, borderRadius = 14),
    child = row(mainAxisSize = msMin, crossAxisAlignment = caEnd,
                children = dots))

proc bubble(m: Message): Widget =
  ## One message bubble. Mine = right-aligned green; theirs =
  ## left-aligned grey. With an imagePath set, the image renders
  ## above the (optional) caption inside the same bubble.
  let bg = if m.mine: bubbleMine else: bubbleThem
  let align = if m.mine: maEnd else: maStart
  var inner: seq[Widget]
  if m.imagePath.len > 0:
    inner.add(clipRRect(radius = 8, child = image(
      m.imagePath, width = 240, height = 180, fit = ifCover)))
    if m.body.len > 0:
      inner.add(sizedBox(height = 6))
  if m.body.len > 0:
    inner.add(text(m.body,
      style = textStyle(fontSize = 14, color = textHi)))
  inner.add(sizedBox(height = 2))
  inner.add(text(m.time,
    style = textStyle(fontSize = 10, color = textLo)))
  row(mainAxisAlignment = align, children = @[
    Widget(container(
      margin = edgeInsetsSymmetric(horizontal = 12, vertical = 3),
      padding = edgeInsetsSymmetric(horizontal = 12, vertical = 8),
      hasDecoration = true,
      decoration = boxDecoration(color = bg, borderRadius = 12),
      child = column(crossAxisAlignment = caEnd, mainAxisSize = msMin,
                     children = inner))),
  ])

proc chatScreen*(): Widget =
  let inputCtrl = newTextEditingController()
  container(hasColor = true, color = bgChat,
    child = column(crossAxisAlignment = caStretch, children = @[
      # Invisible reply-timer host.
      Widget(ReplyTimer()),
      # Header.
      container(
        height = 60,
        hasColor = true, color = bgBar,
        padding = edgeInsetsSymmetric(horizontal = 16, vertical = 8),
        child = row(crossAxisAlignment = caCenter, children = @[
          Widget(container(width = 40, height = 40,
            hasDecoration = true,
            decoration = boxDecoration(color = accent, borderRadius = 20),
            child = center(child = text("F",
              style = textStyle(fontSize = 18, color = colorWhite))))),
          sizedBox(width = 12),
          column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                 children = @[
            Widget(text("Flit Fan Club",
              style = textStyle(fontSize = 16, color = textHi))),
            listenableBuilder(isTyping,
              proc(ctx: BuildContext, t: bool): Widget =
                text(if t: "typing..." else: "online",
                  style = textStyle(fontSize = 11,
                    color = (if t: accent else: textLo)))),
          ]),
        ])),
      # Message list. The ScrollController keeps it pinned to the
      # newest message whenever one lands.
      expanded(child = listenableBuilder(messages,
        proc(ctx: BuildContext, list: seq[Message]): Widget =
          var rows: seq[Widget]
          rows.add(sizedBox(height = 8))
          for m in list:
            rows.add(bubble(m))
          rows.add(listenableBuilder(isTyping,
            proc(ctx: BuildContext, t: bool): Widget =
              if t:
                row(mainAxisAlignment = maStart, children = @[
                  Widget(padding(
                    padding = edgeInsetsSymmetric(horizontal = 12, vertical = 4),
                    child = TypingDots())),
                ])
              else:
                sizedBox(height = 0)))
          rows.add(sizedBox(height = 8))
          scrollView(controller = chatScroll,
            child = column(crossAxisAlignment = caStretch,
                           mainAxisSize = msMin,
                           children = rows)))),
      # Input bar.
      container(
        height = 64,
        hasColor = true, color = bgBar,
        padding = edgeInsetsSymmetric(horizontal = 12, vertical = 12),
        child = row(crossAxisAlignment = caCenter, children = @[
          # Attach image: opens the native picker filtered to images,
          # sends the chosen file with the current input as caption.
          Widget(gestureDetector(behavior = htOpaque,
            onTap = proc() =
              attachImage(inputCtrl.value)
              inputCtrl.value = "",
            child = container(width = 40, height = 40,
              hasDecoration = true,
              decoration = boxDecoration(color = bgChat, borderRadius = 20),
              child = center(child = icon("plus", size = 18,
                color = textLo))))),
          sizedBox(width = 10),
          expanded(child = container(
            hasDecoration = true,
            decoration = boxDecoration(color = bgChat, borderRadius = 20),
            child = padding(
              padding = edgeInsetsSymmetric(horizontal = 12, vertical = 0),
              child = textField(
                controller = inputCtrl,
                placeholder = "Message",
                onSubmitted = proc(v: string) =
                  sendMessage(v)
                  inputCtrl.value = "",
                style = textStyle(fontSize = 14, color = textHi))))),
          sizedBox(width = 10),
          gestureDetector(behavior = htOpaque,
            onTap = proc() =
              sendMessage(inputCtrl.value)
              inputCtrl.value = "",
            child = container(width = 40, height = 40,
              hasDecoration = true,
              decoration = boxDecoration(color = accent, borderRadius = 20),
              child = center(child = icon("chevron.right", size = 20,
                color = colorWhite)))),
        ])),
    ]))

type
  ChatApp = ref object of StatelessWidget

method widgetTypeName(w: ChatApp): string = "ChatApp"
method createElement(w: ChatApp): Element = newElement(ekStateless, w)
method build(w: ChatApp, ctx: BuildContext): Widget =
  chatScreen()

when isMainModule:
  runApp(ChatApp())
