## Layout and painting widgets: the building blocks every Flutter user
## knows. Each widget below is a thin Nim port of the Flutter widget of
## the same name. They form three groups:
##
## 1. Sizing and padding: `sizedBox`, `padding`, `align`, `center`,
##    `constrainedBox`, `aspectRatio`.
## 2. Drawing surfaces: `coloredBox`, `decoratedBox`, `clipRect`,
##    `clipRRect`, `opacity`.
## 3. Multi-child layout: `row`, `column`, `stack`, with `expanded`,
##    `flexible` and `positioned` as parent-data carriers; plus
##    `scrollView` for content that overflows the viewport.
##
## `text` and the high-level `container` round out the file.

import ../foundation/[widget, key, geometry, color, render_object]
import ../rendering/[proxy_box, flex, stack, decoration, text, viewport]

# Container is defined at the END of this file: its build() needs to
# call padding(), align(), decoratedBox(), constrainedBox() and
# sizedBox() which are all defined below.

# ----- SizedBox -----

type
  SizedBox* = ref object of RenderObjectWidget
    ## A widget that forces its child to a specific width and/or height,
    ## or - when no child is given - that simply occupies the given
    ## dimensions as a spacer. A dim of `0.0` means "unspecified".
    width*, height*: float32
    child*: Widget

method widgetTypeName*(w: SizedBox): string = "SizedBox"
method createElement*(w: SizedBox): Element = newElement(ekRender, w)
method createRenderObject*(w: SizedBox, ctx: BuildContext): RenderObject =
  RenderSizedBox(requestedWidth: w.width, requestedHeight: w.height)
method updateRenderObject*(w: SizedBox, ctx: BuildContext, r: RenderObject) =
  let s = RenderSizedBox(r)
  s.requestedWidth = w.width
  s.requestedHeight = w.height
  r.markNeedsLayout()

proc sizedBox*(child: Widget = nil, width = 0.0'f32, height = 0.0'f32,
               key: Key = nil): SizedBox =
  ## Builds a `SizedBox`.
  ##
  ## Inputs:
  ## - `child`: optional widget to wrap. When `nil`, this acts as a spacer.
  ## - `width`, `height`: requested dimensions in logical pixels. A value
  ##   of `0` leaves that axis unspecified - when there's a child it
  ##   passes the parent's constraint through on that axis; when there's
  ##   no child the axis collapses to zero. A positive value tightens
  ##   that axis to exactly the requested size (subject to the parent's
  ##   own tight constraints, which always win).
  ## - `key`: optional reconciliation key. Pass a `Key` if you need this
  ##   widget's state preserved across reorders.
  ##
  ## Effect: lays out the child (if any) within the requested constraints
  ## and paints it at offset `(0, 0)` inside this box.
  SizedBox(key: key, width: width, height: height, child: child)

# ----- Padding -----

type
  Padding* = ref object of RenderObjectWidget
    ## A widget that insets its child by the given `EdgeInsets`. The
    ## parent's constraints are deflated by the insets before being
    ## passed to the child; the child's size is then re-inflated by
    ## the same insets to produce this widget's size.
    padding*: EdgeInsets
    child*: Widget

method widgetTypeName*(w: Padding): string = "Padding"
method createElement*(w: Padding): Element = newElement(ekRender, w)
method createRenderObject*(w: Padding, ctx: BuildContext): RenderObject =
  RenderPadding(padding: w.padding)
method updateRenderObject*(w: Padding, ctx: BuildContext, r: RenderObject) =
  RenderPadding(r).padding = w.padding
  r.markNeedsLayout()

proc padding*(child: Widget = nil, padding = edgeInsetsAll(8),
              key: Key = nil): Padding =
  ## Builds a `Padding` widget around `child`.
  ##
  ## Inputs:
  ## - `child`: widget to inset. May be `nil`, in which case the padding
  ##   is just spacing.
  ## - `padding`: `EdgeInsets` describing the insets on each side.
  ##   Defaults to `edgeInsetsAll(8)`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: subtracts the insets from the inner constraints, lays out
  ## the child, and offsets the child by `(padding.left, padding.top)`
  ## within this widget.
  Padding(key: key, padding: padding, child: child)

# ----- Align / Center -----

type
  Align* = ref object of RenderObjectWidget
    ## A widget that positions its child within itself.
    ##
    ## When `widthFactor` or `heightFactor` are nonzero, this widget
    ## sizes itself to `child.size * factor`. Otherwise it fills the
    ## largest size allowed by its constraints.
    alignment*: Alignment
    widthFactor*, heightFactor*: float32
    child*: Widget

method widgetTypeName*(w: Align): string = "Align"
method createElement*(w: Align): Element = newElement(ekRender, w)
method createRenderObject*(w: Align, ctx: BuildContext): RenderObject =
  RenderAlign(alignment: w.alignment,
              widthFactor: w.widthFactor, heightFactor: w.heightFactor)
method updateRenderObject*(w: Align, ctx: BuildContext, r: RenderObject) =
  let a = RenderAlign(r)
  a.alignment = w.alignment
  a.widthFactor = w.widthFactor
  a.heightFactor = w.heightFactor
  r.markNeedsLayout()

proc align*(child: Widget = nil, alignment = alignCenter,
            widthFactor = 0.0'f32, heightFactor = 0.0'f32,
            key: Key = nil): Align =
  ## Builds an `Align` widget that positions `child` inside itself.
  ##
  ## Inputs:
  ## - `child`: widget to position. May be `nil`, in which case this
  ##   acts as a sized empty box.
  ## - `alignment`: an `Alignment` value such as `alignCenter`,
  ##   `alignTopLeft`, `alignBottomRight`. Determines where the child
  ##   sits inside this widget.
  ## - `widthFactor`: if positive, this widget's width becomes
  ##   `child.size.width * widthFactor`. `0.0` means "expand to fit
  ##   parent constraints".
  ## - `heightFactor`: same idea for height.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: lays out child with loose constraints, then positions it
  ## via `alignment.resolveOffset`.
  Align(key: key, alignment: alignment, widthFactor: widthFactor,
        heightFactor: heightFactor, child: child)

proc center*(child: Widget = nil, key: Key = nil): Align =
  ## Centers `child` within itself. Equivalent to
  ## `align(child = child, alignment = alignCenter)`.
  align(child = child, alignment = alignCenter, key = key)

# ----- ColoredBox -----

type
  ColoredBox* = ref object of RenderObjectWidget
    ## A widget that paints a solid color background then paints its
    ## (optional) child on top. Cheaper than `decoratedBox` for the
    ## solid-color case because it skips border/shadow/radius math.
    color*: Color
    child*: Widget

method widgetTypeName*(w: ColoredBox): string = "ColoredBox"
method createElement*(w: ColoredBox): Element = newElement(ekRender, w)
method createRenderObject*(w: ColoredBox, ctx: BuildContext): RenderObject =
  RenderColoredBox(fill: w.color)
method updateRenderObject*(w: ColoredBox, ctx: BuildContext, r: RenderObject) =
  RenderColoredBox(r).fill = w.color
  r.markNeedsPaint()

proc coloredBox*(child: Widget = nil, color = colorTransparent,
                 key: Key = nil): ColoredBox =
  ## Builds a `ColoredBox` that paints `color` as its background.
  ##
  ## Inputs:
  ## - `child`: widget painted on top of the background. May be `nil`.
  ## - `color`: fill color. Defaults to `colorTransparent`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: draws a rectangle the size of this widget in `color`, then
  ## paints the child unchanged.
  ColoredBox(key: key, color: color, child: child)

# ----- DecoratedBox -----

type
  DecoratedBox* = ref object of RenderObjectWidget
    ## A widget that paints a `BoxDecoration` (color, border-radius,
    ## border, shadows, shape) under or over its child. Currently
    ## decorations always paint underneath.
    decoration*: BoxDecoration
    child*: Widget

method widgetTypeName*(w: DecoratedBox): string = "DecoratedBox"
method createElement*(w: DecoratedBox): Element = newElement(ekRender, w)
method createRenderObject*(w: DecoratedBox, ctx: BuildContext): RenderObject =
  RenderDecoratedBox(decoration: w.decoration)
method updateRenderObject*(w: DecoratedBox, ctx: BuildContext, r: RenderObject) =
  RenderDecoratedBox(r).decoration = w.decoration
  r.markNeedsPaint()

proc decoratedBox*(child: Widget = nil, decoration = BoxDecoration(),
                   key: Key = nil): DecoratedBox =
  ## Builds a `DecoratedBox` that paints `decoration` behind `child`.
  ##
  ## Inputs:
  ## - `child`: widget painted on top of the decoration. May be `nil`,
  ##   in which case the box renders just the decoration filling its
  ##   constraints.
  ## - `decoration`: a `BoxDecoration` built via `boxDecoration(...)`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: draws shadows, then the fill (rrect / rect / circle
  ## depending on `borderRadius` and `shape`), then the border, then
  ## the child.
  DecoratedBox(key: key, decoration: decoration, child: child)

# ----- Row / Column -----

type
  Row* = ref object of RenderObjectWidget
    ## Horizontal flex container. Lays children out left-to-right.
    ## Equivalent to Flutter's `Row`.
    mainAxisAlignment*: MainAxisAlignment
    crossAxisAlignment*: CrossAxisAlignment
    mainAxisSize*: MainAxisSize
    children*: seq[Widget]

  Column* = ref object of RenderObjectWidget
    ## Vertical flex container. Lays children out top-to-bottom.
    ## Equivalent to Flutter's `Column`.
    mainAxisAlignment*: MainAxisAlignment
    crossAxisAlignment*: CrossAxisAlignment
    mainAxisSize*: MainAxisSize
    children*: seq[Widget]

method widgetTypeName*(w: Row): string = "Row"
method widgetTypeName*(w: Column): string = "Column"
method createElement*(w: Row): Element = newElement(ekRender, w)
method createElement*(w: Column): Element = newElement(ekRender, w)
method createRenderObject*(w: Row, ctx: BuildContext): RenderObject =
  RenderFlex(direction: axHorizontal,
             mainAxisAlignment: w.mainAxisAlignment,
             crossAxisAlignment: w.crossAxisAlignment,
             mainAxisSize: w.mainAxisSize)
method createRenderObject*(w: Column, ctx: BuildContext): RenderObject =
  RenderFlex(direction: axVertical,
             mainAxisAlignment: w.mainAxisAlignment,
             crossAxisAlignment: w.crossAxisAlignment,
             mainAxisSize: w.mainAxisSize)
method updateRenderObject*(w: Row, ctx: BuildContext, r: RenderObject) =
  let f = RenderFlex(r)
  f.mainAxisAlignment = w.mainAxisAlignment
  f.crossAxisAlignment = w.crossAxisAlignment
  f.mainAxisSize = w.mainAxisSize
  r.markNeedsLayout()
method updateRenderObject*(w: Column, ctx: BuildContext, r: RenderObject) =
  let f = RenderFlex(r)
  f.mainAxisAlignment = w.mainAxisAlignment
  f.crossAxisAlignment = w.crossAxisAlignment
  f.mainAxisSize = w.mainAxisSize
  r.markNeedsLayout()

proc row*(children: seq[Widget] = @[],
          mainAxisAlignment = maStart, crossAxisAlignment = caCenter,
          mainAxisSize = msMax, key: Key = nil): Row =
  ## Builds a `Row` (horizontal flex container).
  ##
  ## Inputs:
  ## - `children`: ordered list of widgets to lay out left-to-right.
  ##   Wrap a child in `expanded(...)` or `flexible(...)` to give it
  ##   a flex weight.
  ## - `mainAxisAlignment`: horizontal placement of children. One of
  ##   `maStart`, `maEnd`, `maCenter`, `maSpaceBetween`,
  ##   `maSpaceAround`, `maSpaceEvenly`. Default `maStart`.
  ## - `crossAxisAlignment`: vertical placement of children within the
  ##   row's height. One of `caStart`, `caEnd`, `caCenter`, `caStretch`,
  ##   `caBaseline`. Default `caCenter`.
  ## - `mainAxisSize`: `msMax` to fill the parent's horizontal extent,
  ##   `msMin` to shrink-wrap the children. Default `msMax`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: two-pass layout. Pass 1 measures inflexible children. Pass 2
  ## distributes remaining space across flex children weighted by their
  ## `flex` values.
  Row(key: key, children: children,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize)

proc column*(children: seq[Widget] = @[],
             mainAxisAlignment = maStart, crossAxisAlignment = caCenter,
             mainAxisSize = msMax, key: Key = nil): Column =
  ## Builds a `Column` (vertical flex container).
  ##
  ## Inputs:
  ## - `children`: ordered list of widgets to lay out top-to-bottom.
  ## - `mainAxisAlignment`: vertical placement (same enum values as
  ##   `row`, applied along Y).
  ## - `crossAxisAlignment`: horizontal placement within the column's
  ##   width. Use `caStretch` to make children fill the column width.
  ## - `mainAxisSize`: `msMax` fills parent height, `msMin` shrink-wraps
  ##   children. Use `msMin` for inner columns inside cards or scrollable
  ##   content to avoid eating all available vertical space.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: same two-pass flex layout as `row`, applied along Y.
  Column(key: key, children: children,
         mainAxisAlignment: mainAxisAlignment,
         crossAxisAlignment: crossAxisAlignment,
         mainAxisSize: mainAxisSize)

# ----- Expanded / Flexible -----

type
  Flexible* = ref object of ProxyWidget
    ## A parent-data widget for `Row` and `Column` children. Tells the
    ## flex container how much of the remaining main-axis space this
    ## child should claim (`flex`), and whether the child must take
    ## exactly that space (`fit = ffTight`) or may be smaller
    ## (`fit = ffLoose`).
    flex*: int
    fit*: FlexFit

method widgetTypeName*(w: Flexible): string = "Flexible"
method createElement*(w: Flexible): Element = newElement(ekProxy, w)

proc flexible*(child: Widget, flex = 1, fit = ffLoose, key: Key = nil): Flexible =
  ## Wraps `child` for placement inside `row` or `column` with flex
  ## behavior.
  ##
  ## Inputs:
  ## - `child`: the widget to flex. Required.
  ## - `flex`: relative weight against other flex siblings. Two children
  ##   with flex 1 and 2 split remaining space 1/3 and 2/3. Default `1`.
  ## - `fit`: `ffLoose` lets the child be smaller than its allocation
  ##   (it gets a max constraint but no min). `ffTight` forces the child
  ##   to exactly fill its allocated extent. Default `ffLoose`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: contributes parent data to the enclosing flex container so
  ## the layout pass distributes space proportionally.
  Flexible(key: key, child: child, flex: flex, fit: fit)

proc expanded*(child: Widget, flex = 1, key: Key = nil): Flexible =
  ## Convenience for `flexible(child, flex = flex, fit = ffTight)`. The
  ## child fills its allocated extent exactly. Matches Flutter's
  ## `Expanded`.
  flexible(child = child, flex = flex, fit = ffTight, key = key)

# ----- Positioned (Stack child) -----

type
  Positioned* = ref object of ProxyWidget
    ## Parent-data widget for `Stack` children. Any combination of
    ## `left`, `top`, `right`, `bottom`, `width`, `height` may be set.
    ## Unspecified dimensions default to `unsetF` (NaN) and let the
    ## opposing side / size compute the layout. Mirrors Flutter's
    ## `Positioned`.
    left*, top*, right*, bottom*, width*, height*: float32

method widgetTypeName*(w: Positioned): string = "Positioned"
method createElement*(w: Positioned): Element = newElement(ekProxy, w)

proc positioned*(child: Widget,
                 left = unsetF, top = unsetF, right = unsetF,
                 bottom = unsetF, width = unsetF, height = unsetF,
                 key: Key = nil): Positioned =
  ## Anchors `child` inside an enclosing `Stack` using absolute offsets.
  ##
  ## Inputs:
  ## - `child`: widget to position. Required.
  ## - `left`, `top`, `right`, `bottom`: distance in logical pixels from
  ##   the corresponding edge of the stack. Pass `unsetF` (the default)
  ##   to leave a side unconstrained.
  ## - `width`, `height`: explicit size. When unset, the size derives
  ##   from the opposing pair (e.g. `left` and `right`) or from the
  ##   child's intrinsic size.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: tells the parent `Stack` to position this child at the
  ## resolved offset and (if both opposing edges are set) at a derived
  ## tight size.
  Positioned(key: key, child: child, left: left, top: top, right: right,
             bottom: bottom, width: width, height: height)

# ----- Stack -----

type
  Stack* = ref object of RenderObjectWidget
    ## Z-order layout container. Children paint back-to-front in the
    ## order they appear in `children`; `positioned` children are
    ## absolutely placed, while non-positioned children align using
    ## `alignment`. Matches Flutter's `Stack`.
    alignment*: Alignment
    fit*: StackFit
    children*: seq[Widget]

method widgetTypeName*(w: Stack): string = "Stack"
method createElement*(w: Stack): Element = newElement(ekRender, w)
method createRenderObject*(w: Stack, ctx: BuildContext): RenderObject =
  RenderStack(alignment: w.alignment, fit: w.fit)
method updateRenderObject*(w: Stack, ctx: BuildContext, r: RenderObject) =
  let st = RenderStack(r)
  st.alignment = w.alignment
  st.fit = w.fit
  r.markNeedsLayout()

proc stack*(children: seq[Widget] = @[], alignment = alignTopLeft,
            fit = sfLoose, key: Key = nil): Stack =
  ## Builds a `Stack` layered layout.
  ##
  ## Inputs:
  ## - `children`: bottom-to-top list. Index 0 paints first (background),
  ##   subsequent children paint above. Hit testing iterates top-down so
  ##   the visually-topmost child catches events first.
  ## - `alignment`: alignment for any non-`positioned` children. Default
  ##   `alignTopLeft`.
  ## - `fit`: how non-positioned children size themselves.
  ##   - `sfLoose` (default): children get loose constraints.
  ##   - `sfExpand`: children get tight max-size constraints (fill).
  ##   - `sfPassthrough`: children get the stack's own constraints.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: sizes itself to the largest non-positioned child, then
  ## places positioned children at their absolute offsets.
  Stack(key: key, children: children, alignment: alignment, fit: fit)

# ----- ScrollView -----

type
  ScrollView* = ref object of RenderObjectWidget
    ## A scrollable viewport. Lays its child out with unbounded main-axis
    ## constraints, then clips painting to its own bounds and translates
    ## the child by `-scrollOffset`. Mouse-wheel events delivered while
    ## the pointer is over this widget update its offset.
    child*: Widget
    direction*: Axis

method widgetTypeName*(w: ScrollView): string = "ScrollView"
method createElement*(w: ScrollView): Element = newElement(ekRender, w)
method createRenderObject*(w: ScrollView, ctx: BuildContext): RenderObject =
  RenderViewport(direction: w.direction, scrollOffset: 0, maxScroll: 0)
method updateRenderObject*(w: ScrollView, ctx: BuildContext, r: RenderObject) =
  RenderViewport(r).direction = w.direction
  r.markNeedsLayout()

proc scrollView*(child: Widget, direction = axVertical,
                 key: Key = nil): ScrollView =
  ## Builds a scrollable area around `child`.
  ##
  ## Inputs:
  ## - `child`: content that may be larger than the viewport in the
  ##   scroll direction.
  ## - `direction`: `axVertical` for vertical scrolling (the default,
  ##   matches Flutter's `SingleChildScrollView` default) or
  ##   `axHorizontal`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: child is laid out with unbounded extent along `direction`
  ## and the parent's tight extent on the cross axis. Painting is
  ## clipped to the viewport bounds. A thin dark scrollbar thumb on the
  ## trailing edge indicates current position when the content overflows.
  ScrollView(key: key, child: child, direction: direction)

# ----- Text -----

type
  Text* = ref object of RenderObjectWidget
    ## A widget that displays a string of text with the given style and
    ## alignment. Supports soft-wrapping by word with optional `maxLines`
    ## clamping.
    data*: string
    style*: TextStyle
    textAlign*: TextAlign
    softWrap*: bool
    maxLines*: int

method widgetTypeName*(w: Text): string = "Text"
method createElement*(w: Text): Element = newElement(ekRender, w)
method createRenderObject*(w: Text, ctx: BuildContext): RenderObject =
  RenderParagraph(text: w.data, style: w.style, align: w.textAlign,
                  maxLines: w.maxLines, softWrap: w.softWrap)
method updateRenderObject*(w: Text, ctx: BuildContext, r: RenderObject) =
  let p = RenderParagraph(r)
  p.text = w.data
  p.style = w.style
  p.align = w.textAlign
  p.softWrap = w.softWrap
  p.maxLines = w.maxLines
  p.markNeedsLayout()

proc text*(data: string, style = defaultTextStyle,
           textAlign = taStart, softWrap = true, maxLines = 0,
           key: Key = nil): Text =
  ## Builds a `Text` widget.
  ##
  ## Inputs:
  ## - `data`: the string to display.
  ## - `style`: a `TextStyle` built via `textStyle(...)`. Defaults to
  ##   `defaultTextStyle` (14pt, system font, black, weight 400).
  ## - `textAlign`: alignment of each line within the widget's width.
  ##   `taStart`/`taLeft`, `taEnd`/`taRight`, `taCenter`, `taJustify`.
  ## - `softWrap`: if `true` (default) text wraps at word boundaries
  ##   when it would exceed `constraints.maxWidth`. If `false` the text
  ##   stays on one line (and may overflow).
  ## - `maxLines`: cap on the number of lines after wrapping. `0` (the
  ##   default) means unlimited.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: measures the text via the active `measureText` proc, wraps
  ## as needed, and paints each line at the appropriate horizontal offset
  ## according to `textAlign`.
  Text(key: key, data: data, style: style, textAlign: textAlign,
       softWrap: softWrap, maxLines: maxLines)

# ----- ConstrainedBox -----

type
  ConstrainedBox* = ref object of RenderObjectWidget
    ## Imposes additional `Constraints` on the child beyond what the
    ## parent already gave. Used to set a min/max width or height that
    ## may be tighter than the surrounding layout.
    boxConstraints*: Constraints
    child*: Widget

method widgetTypeName*(w: ConstrainedBox): string = "ConstrainedBox"
method createElement*(w: ConstrainedBox): Element = newElement(ekRender, w)
method createRenderObject*(w: ConstrainedBox, ctx: BuildContext): RenderObject =
  RenderConstrainedBox(additionalConstraints: w.boxConstraints)

proc constrainedBox*(child: Widget, boxConstraints: Constraints,
                     key: Key = nil): ConstrainedBox =
  ## Builds a `ConstrainedBox` that imposes `boxConstraints` on top of
  ## the parent's.
  ##
  ## Inputs:
  ## - `child`: widget to wrap. Required.
  ## - `boxConstraints`: additional `Constraints`, built via
  ##   `constraints(minW, maxW, minH, maxH)` or `tightFor(w, h)`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: combines the parent's constraints with `boxConstraints` via
  ## `enforce`. The parent's tight constraints always win in case of
  ## conflict (matching Flutter).
  ConstrainedBox(key: key, child: child, boxConstraints: boxConstraints)

# ----- AspectRatio -----

type
  AspectRatio* = ref object of RenderObjectWidget
    ## Sizes its child to a fixed width-to-height ratio while still
    ## obeying the parent's constraints. Equivalent to Flutter's
    ## `AspectRatio`.
    aspectRatio*: float32
    child*: Widget

method widgetTypeName*(w: AspectRatio): string = "AspectRatio"
method createElement*(w: AspectRatio): Element = newElement(ekRender, w)
method createRenderObject*(w: AspectRatio, ctx: BuildContext): RenderObject =
  RenderAspectRatio(aspectRatio: w.aspectRatio)
method updateRenderObject*(w: AspectRatio, ctx: BuildContext, r: RenderObject) =
  RenderAspectRatio(r).aspectRatio = w.aspectRatio
  r.markNeedsLayout()

proc aspectRatio*(child: Widget, aspectRatio: float32,
                  key: Key = nil): AspectRatio =
  ## Builds an `AspectRatio` widget.
  ##
  ## Inputs:
  ## - `child`: widget to size.
  ## - `aspectRatio`: width / height. For example `2.0` for a 2:1
  ##   landscape box, `0.5` for portrait.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: chooses the largest size that fits the parent's constraints
  ## and matches the requested ratio. If both axes are unbounded, falls
  ## back to width-driven sizing using the parent's max width.
  AspectRatio(key: key, child: child, aspectRatio: aspectRatio)

# ----- ClipRect / ClipRRect / Opacity widgets -----

type
  ClipRect* = ref object of RenderObjectWidget
    ## Clips the child's painting to this widget's bounds. Useful when
    ## the child overflows its own constraints and you want a hard cut.
    child*: Widget

  ClipRRect* = ref object of RenderObjectWidget
    ## Like `ClipRect` but with rounded corners of the given `radius`.
    ## On backends that lack rounded clipping the clip falls back to
    ## a rectangular clip (visible square corners).
    radius*: float32
    child*: Widget

  OpacityWidget* = ref object of RenderObjectWidget
    ## Makes the child translucent. Every primitive painted inside the
    ## subtree has its alpha channel multiplied by `opacity`.
    opacity*: float32
    child*: Widget

method widgetTypeName*(w: ClipRect): string = "ClipRect"
method createElement*(w: ClipRect): Element = newElement(ekRender, w)
method createRenderObject*(w: ClipRect, ctx: BuildContext): RenderObject =
  RenderClipRect()

method widgetTypeName*(w: ClipRRect): string = "ClipRRect"
method createElement*(w: ClipRRect): Element = newElement(ekRender, w)
method createRenderObject*(w: ClipRRect, ctx: BuildContext): RenderObject =
  RenderClipRRect(radius: w.radius)
method updateRenderObject*(w: ClipRRect, ctx: BuildContext, r: RenderObject) =
  RenderClipRRect(r).radius = w.radius
  r.markNeedsPaint()

method widgetTypeName*(w: OpacityWidget): string = "Opacity"
method createElement*(w: OpacityWidget): Element = newElement(ekRender, w)
method createRenderObject*(w: OpacityWidget, ctx: BuildContext): RenderObject =
  RenderOpacity(opacity: w.opacity)
method updateRenderObject*(w: OpacityWidget, ctx: BuildContext, r: RenderObject) =
  RenderOpacity(r).opacity = w.opacity
  r.markNeedsPaint()

proc clipRect*(child: Widget, key: Key = nil): ClipRect =
  ## Builds a `ClipRect` around `child`. The child paints normally; any
  ## drawing outside this widget's bounds is cut off.
  ClipRect(key: key, child: child)

proc clipRRect*(child: Widget, radius: float32, key: Key = nil): ClipRRect =
  ## Builds a `ClipRRect` (rounded-rectangle clip) around `child`.
  ##
  ## Inputs:
  ## - `child`: widget whose painting will be clipped.
  ## - `radius`: corner radius in logical pixels.
  ## - `key`: optional reconciliation key.
  ClipRRect(key: key, child: child, radius: radius)

# ----- RepaintBoundary -----

type
  RepaintBoundary* = ref object of RenderObjectWidget
    ## A widget that promotes its subtree to its own cached layer.
    ## The subtree is rasterized to an off-screen surface once and
    ## composited (GPU-side on the SDL desktop backend) on every
    ## subsequent frame until something inside calls
    ## `markNeedsPaint`. Mirrors Flutter's `RepaintBoundary`.
    ##
    ## Use this around subtrees that paint a lot of pixels but
    ## rarely change relative to their surroundings: card lists,
    ## decorative backgrounds, complex shadows behind animated UI.
    ## Overusing it costs memory (one GPU texture per boundary);
    ## underusing it costs frame time (every pixel re-rasterized
    ## per frame).
    child*: Widget

method widgetTypeName*(w: RepaintBoundary): string = "RepaintBoundary"
method createElement*(w: RepaintBoundary): Element = newElement(ekRender, w)
method createRenderObject*(w: RepaintBoundary, ctx: BuildContext): RenderObject =
  RenderRepaintBoundary()
method updateRenderObject*(w: RepaintBoundary, ctx: BuildContext, r: RenderObject) =
  ## Nothing config-driven to update; the cache stays valid across
  ## widget identity changes as long as the subtree layout matches.
  discard

proc repaintBoundary*(child: Widget, key: Key = nil): RepaintBoundary =
  ## Builds a `RepaintBoundary` around `child`.
  ##
  ## Inputs:
  ## - `child`: subtree to cache. Required.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: subtree is rasterized into an off-screen sub-canvas on
  ## first paint; subsequent frames composite the cached surface
  ## directly. The cache is invalidated automatically whenever any
  ## descendant calls `markNeedsPaint` (including via `setState`).
  RepaintBoundary(key: key, child: child)

# ----- Transform -----

type
  TransformWidget* = ref object of RenderObjectWidget
    ## Applies a translate + rotate + scale to its child's paint.
    ## Mirrors Flutter's `Transform`. Fields default to identity.
    translation*: Offset
    rotation*:    float32
    scaleX*:      float32
    child*:       Widget

method widgetTypeName*(w: TransformWidget): string = "Transform"
method createElement*(w: TransformWidget): Element = newElement(ekRender, w)
method createRenderObject*(w: TransformWidget, ctx: BuildContext): RenderObject =
  RenderTransform(translation: w.translation, rotation: w.rotation,
                  scale: w.scaleX)
method updateRenderObject*(w: TransformWidget, ctx: BuildContext, r: RenderObject) =
  let t = RenderTransform(r)
  t.translation = w.translation
  t.rotation = w.rotation
  t.scale = w.scaleX
  r.markNeedsPaint()

proc transform*(child: Widget,
                translation: Offset = Offset(dx: 0, dy: 0),
                rotation: float32 = 0,
                scale: float32 = 1,
                key: Key = nil): TransformWidget =
  ## Wraps `child` in a transform.
  ##
  ## Inputs:
  ## - `child`: subtree to transform.
  ## - `translation`: shift in pixels. Identity is `(0, 0)`.
  ## - `rotation`: rotation in radians around the widget's
  ##   top-left. Identity is `0`.
  ## - `scale`: uniform scale factor. `1` is identity; `0` is also
  ##   treated as identity to avoid collapsing the widget.
  ## - `key`: reconciliation key.
  TransformWidget(key: key, child: child, translation: translation,
                  rotation: rotation, scaleX: scale)

proc opacity*(child: Widget, opacity: float32, key: Key = nil): OpacityWidget =
  ## Builds an `OpacityWidget` that fades `child`.
  ##
  ## Inputs:
  ## - `child`: subtree to attenuate.
  ## - `opacity`: 0.0 (fully transparent) to 1.0 (fully opaque). Values
  ##   outside this range are clamped.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: pushes a multiplier onto the canvas opacity stack before
  ## painting the child, pops afterwards. Nested `opacity` widgets
  ## multiply (so 0.5 nested in 0.5 yields 0.25).
  OpacityWidget(key: key, child: child, opacity: opacity)

# ----- Container -----
#
# Convenience composite that builds the standard Flutter composition:
#   margin > decoration > constrained > padding > align > child.
# Each layer is skipped if not requested. Defined at end of file because
# its build() needs the constructors above (padding, align, decoratedBox,
# constrainedBox, sizedBox) to be in scope.

type
  Container* = ref object of StatelessWidget
    ## High-level widget that composes the most common chain of layout
    ## and decoration widgets: `margin > decoration > constrained >
    ## padding > align > child`. Mirrors Flutter's `Container`.
    ##
    ## Only the layers that are requested are built; if no fields are
    ## set the container collapses to a `sizedBox()`.
    width*, height*: float32
    padding*, margin*: EdgeInsets
    color*: Color
    decoration*: BoxDecoration
    alignment*: Alignment
    child*: Widget
    hasAlignment*: bool
    hasDecoration*: bool
    hasColor*: bool

method widgetTypeName*(w: Container): string = "Container"
method createElement*(w: Container): Element = newElement(ekStateless, w)
method build*(w: Container, ctx: BuildContext): Widget =
  var current = w.child

  if w.hasAlignment and not current.isNil:
    current = align(child = current, alignment = w.alignment)

  if w.padding.left != 0 or w.padding.top != 0 or
     w.padding.right != 0 or w.padding.bottom != 0:
    current = padding(child = current, padding = w.padding)

  if w.width > 0 or w.height > 0:
    let minW = if w.width  > 0: w.width  else: 0.0'f32
    let maxW = if w.width  > 0: w.width  else: Inf
    let minH = if w.height > 0: w.height else: 0.0'f32
    let maxH = if w.height > 0: w.height else: Inf
    if current.isNil:
      current = sizedBox(width = w.width, height = w.height)
    else:
      current = constrainedBox(child = current,
                               boxConstraints = constraints(minW, maxW, minH, maxH))

  if w.hasDecoration:
    if not current.isNil:
      current = decoratedBox(child = current, decoration = w.decoration)
    else:
      current = decoratedBox(decoration = w.decoration)
  elif w.hasColor:
    let dec = boxDecoration(color = w.color)
    if not current.isNil:
      current = decoratedBox(child = current, decoration = dec)
    else:
      current = decoratedBox(decoration = dec)

  if w.margin.left != 0 or w.margin.top != 0 or
     w.margin.right != 0 or w.margin.bottom != 0:
    current = padding(child = current, padding = w.margin)

  if current.isNil: current = sizedBox()
  current

proc container*(child: Widget = nil,
                width = 0.0'f32, height = 0.0'f32,
                color = colorTransparent,
                padding = edgeInsetsAll(0),
                margin = edgeInsetsAll(0),
                alignment = alignCenter,
                decoration = BoxDecoration(),
                hasColor = false,
                hasDecoration = false,
                hasAlignment = false,
                key: Key = nil): Container =
  ## Builds a `Container`, the swiss-army-knife layout widget.
  ##
  ## Every parameter is optional; pass only what you need. The widget
  ## skips the corresponding chain layer if it isn't requested.
  ##
  ## Inputs:
  ## - `child`: optional inner widget.
  ## - `width`, `height`: explicit dimensions in logical pixels. `0`
  ##   leaves the axis unconstrained.
  ## - `color`: shorthand for a solid background. Requires
  ##   `hasColor = true` to take effect (so `colorTransparent` defaults
  ##   don't silently apply a fill).
  ## - `padding`: insets between the decoration and the child.
  ## - `margin`: insets outside the decoration.
  ## - `alignment`: how the child is aligned inside the container.
  ##   Requires `hasAlignment = true`.
  ## - `decoration`: a full `BoxDecoration` (color, radius, border,
  ##   shadows). Requires `hasDecoration = true`. Takes precedence over
  ##   `color`.
  ## - `hasColor`, `hasDecoration`, `hasAlignment`: explicit opt-ins so
  ##   that default zero values don't accidentally enable a layer.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: builds a widget tree shaped like Flutter's `Container`:
  ## `margin > decoration > constrained > padding > align > child`.
  Container(key: key, width: width, height: height, color: color,
            padding: padding, margin: margin, alignment: alignment,
            decoration: decoration, child: child,
            hasColor: hasColor, hasDecoration: hasDecoration,
            hasAlignment: hasAlignment)
