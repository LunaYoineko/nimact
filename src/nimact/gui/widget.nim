## =============================================================================
## nimact/gui/widget.nim
## Flutter 風の宣言型 GUI ウィジェットシステム
##
## ウィジェットツリーを宣言的に構築し、
## 制約ベースのレイアウトと描画を行う:
##   - ウィジェット型: Container, Text, Row, Column, Stack, Center,
##                     Expanded, Button, GestureDetector, Scaffold
##   - ビルダー関数: 言語的に自然な DSL でツリーを構築
##   - State: StatefulWidget パターン (setState で再ビルド)
##   - Layout: 制約を下に渡し、サイズを上に返す 2 フェーズ
##   - Paint: GraphicsContext に描画
## =============================================================================

import std/tables
import std/strutils
import ../core/graphics
import ../core/text

# =============================================================================
# Forward declarations
# =============================================================================

type
  WidgetKind* = enum
    wkContainer, wkText, wkRow, wkColumn, wkStack,
    wkCenter, wkExpanded, wkSpacer,
    wkButton, wkGestureDetector, wkScaffold,
    wkSizedBox, wkPadding, wkAlign, wkCard,
    wkProgressBar, wkImage

  Insets* = object
    top*, right*, bottom*, left*: int

  Alignment* = object
    x*, y*: float

  MainAxisAlignment* = enum
    msaStart, msaEnd, msaCenter, msaSpaceBetween, msaSpaceAround, msaSpaceEvenly

  CrossAxisAlignment* = enum
    csaStart, csaEnd, csaCenter, csaStretch

  TextStyle* = object
    fontSize*: int
    fontWeight*: FontWeight
    color*: Color
    fontFamily*: string

  FontWeight* = enum
    fwThin, fwLight, fwRegular, fwMedium, fwBold, fwBlack

  BoxDecoration* = object
    color*: Color
    borderRadius*: int
    border*: BorderStyleDeco
    borderColor*: Color
    borderWidth*: int
    gradient*: GradientStyle

  BorderStyleDeco* = enum
    bsNone, bsSolid

  GradientStyle* = object
    enabled*: bool
    topColor*, bottomColor*: Color

  ButtonStyle* = object
    backgroundColor*: Color
    foregroundColor*: Color
    borderRadius*: int
    padding*: Insets
    elevation*: int
    hoverColor*: Color
    pressedColor*: Color

  AppBarConfig* = object
    title*: string
    bgColor*: Color
    fgColor*: Color
    height*: int

  LayoutConstraints* = object
    minWidth*, maxWidth*: int
    minHeight*, maxHeight*: int

  LayoutSize* = object
    width*, height*: int

  HitTestResult* = object
    hit*: bool
    x*, y*: int

  Widget* = ref object
    case kind*: WidgetKind
    of wkContainer:
      contChild*: Widget
      contPadding*: Insets
      contMargin*: Insets
      contWidth*, contHeight*: int
      contAlignment*: Alignment
      contDecoration*: BoxDecoration
    of wkText:
      txtContent*: string
      txtStyle*: TextStyle
      txtMaxWidth*: int
    of wkRow:
      rowChildren*: seq[Widget]
      rowSpacing*: int
      rowMainAlign*: MainAxisAlignment
      rowCrossAlign*: CrossAxisAlignment
    of wkColumn:
      colChildren*: seq[Widget]
      colSpacing*: int
      colMainAlign*: MainAxisAlignment
      colCrossAlign*: CrossAxisAlignment
    of wkStack:
      stkChildren*: seq[Widget]
      stkAlignment*: Alignment
    of wkCenter:
      centerChild*: Widget
      centerWidth*, centerHeight*: int
    of wkExpanded:
      expChild*: Widget
      expFlex*: int
    of wkSpacer:
      spacerFlex*: int
    of wkButton:
      btnLabel*: string
      btnOnPressed*: proc()
      btnStyle*: ButtonStyle
      btnIcon*: string
    of wkGestureDetector:
      gdChild*: Widget
      gdOnTap*: proc()
      gdOnHover*: proc(hovered: bool)
    of wkScaffold:
      scfAppBar*: AppBarConfig
      scfBody*: Widget
      scfFloatingAction*: Widget
    of wkSizedBox:
      swChild*: Widget
      swWidth*, swHeight*: int
    of wkPadding:
      padChild*: Widget
      padInsets*: Insets
    of wkAlign:
      alChild*: Widget
      alAlignment*: Alignment
      alWidth*, alHeight*: int
    of wkCard:
      cardChild*: Widget
      cardPadding*: Insets
      cardMargin*: Insets
      cardRadius*: int
      cardColor*: Color
    of wkProgressBar:
      pbValue*: float
      pbHeight*: int
      pbColor*, pbTrackColor*: Color
      pbRadius*: int
    of wkImage:
      imgData*: seq[uint32]
      imgWidth*, imgHeight*: int

# =============================================================================
# Insets constructors
# =============================================================================

proc `insets`*(all: int): Insets =
  Insets(top: all, right: all, bottom: all, left: all)

proc `insets`*(vertical, horizontal: int): Insets =
  Insets(top: vertical, right: horizontal, bottom: vertical, left: horizontal)

proc `insets`*(top, right, bottom, left: int): Insets =
  Insets(top: top, right: right, bottom: bottom, left: left)

proc horizontal*(insets: Insets): int = insets.left + insets.right
proc vertical*(insets: Insets): int = insets.top + insets.bottom

# =============================================================================
# Alignment constructors
# =============================================================================

const
  alTopLeft*     = Alignment(x: -1.0, y: -1.0)
  alTopCenter*   = Alignment(x:  0.0, y: -1.0)
  alTopRight*    = Alignment(x:  1.0, y: -1.0)
  alCenterLeft*  = Alignment(x: -1.0, y:  0.0)
  alCenter*      = Alignment(x:  0.0, y:  0.0)
  alCenterRight* = Alignment(x:  1.0, y:  0.0)
  alBottomLeft*   = Alignment(x: -1.0, y:  1.0)
  alBottomCenter* = Alignment(x:  0.0, y:  1.0)
  alBottomRight*  = Alignment(x:  1.0, y:  1.0)

proc alignment*(x, y: float): Alignment =
  Alignment(x: x, y: y)

# =============================================================================
# TextStyle constructors
# =============================================================================

proc textStyle*(size: int = 16, color: Color = colText,
                weight: FontWeight = fwRegular): TextStyle =
  TextStyle(fontSize: size, color: color, fontWeight: weight)

# =============================================================================
# ButtonStyle constructors
# =============================================================================

proc buttonStyle*(bg: Color = colBlue, fg: Color = colWhite,
                  radius: int = 8): ButtonStyle =
  ButtonStyle(
    backgroundColor: bg,
    foregroundColor: fg,
    borderRadius: radius,
    padding: insets(12, 24),
    elevation: 2,
    hoverColor: colBgHover,
    pressedColor: colBgPressed
  )

# =============================================================================
# Widget builder functions (Flutter-like DSL)
# =============================================================================

proc container*(child: Widget = nil,
                padding: Insets = Insets(),
                margin: Insets = Insets(),
                width, height: int = -1,
                alignment: Alignment = alCenter,
                decoration: BoxDecoration = BoxDecoration()): Widget =
  Widget(kind: wkContainer, contChild: child, contPadding: padding,
         contMargin: margin, contWidth: width, contHeight: height,
         contAlignment: alignment, contDecoration: decoration)

proc text*(content: string,
           style: TextStyle = textStyle(),
           maxWidth: int = -1): Widget =
  Widget(kind: wkText, txtContent: content, txtStyle: style, txtMaxWidth: maxWidth)

proc row*(children: varargs[Widget]): Widget =
  Widget(kind: wkRow, rowChildren: @children, rowSpacing: 0,
         rowMainAlign: msaStart, rowCrossAlign: csaCenter)

proc row*(spacing: int; children: varargs[Widget]): Widget =
  Widget(kind: wkRow, rowChildren: @children, rowSpacing: spacing,
         rowMainAlign: msaStart, rowCrossAlign: csaCenter)

proc row*(spacing: int; mainAlign: MainAxisAlignment; crossAlign: CrossAxisAlignment;
          children: varargs[Widget]): Widget =
  Widget(kind: wkRow, rowChildren: @children, rowSpacing: spacing,
         rowMainAlign: mainAlign, rowCrossAlign: crossAlign)

proc column*(children: varargs[Widget]): Widget =
  Widget(kind: wkColumn, colChildren: @children, colSpacing: 0,
         colMainAlign: msaStart, colCrossAlign: csaStart)

proc column*(spacing: int; children: varargs[Widget]): Widget =
  Widget(kind: wkColumn, colChildren: @children, colSpacing: spacing,
         colMainAlign: msaStart, colCrossAlign: csaStart)

proc column*(spacing: int; mainAlign: MainAxisAlignment; crossAlign: CrossAxisAlignment;
             children: varargs[Widget]): Widget =
  Widget(kind: wkColumn, colChildren: @children, colSpacing: spacing,
         colMainAlign: mainAlign, colCrossAlign: crossAlign)

proc stack*(children: varargs[Widget]): Widget =
  Widget(kind: wkStack, stkChildren: @children, stkAlignment: alTopLeft)

proc center*(child: Widget,
             width, height: int = -1): Widget =
  Widget(kind: wkCenter, centerChild: child, centerWidth: width, centerHeight: height)

proc expanded*(child: Widget, flex: int = 1): Widget =
  Widget(kind: wkExpanded, expChild: child, expFlex: flex)

proc spacer*(flex: int = 1): Widget =
  Widget(kind: wkSpacer, spacerFlex: flex)

proc button*(label: string, onPressed: proc() = nil,
             style: ButtonStyle = buttonStyle(),
             icon: string = ""): Widget =
  Widget(kind: wkButton, btnLabel: label, btnOnPressed: onPressed,
         btnStyle: style, btnIcon: icon)

proc gestureDetector*(child: Widget,
                      onTap: proc() = nil,
                      onHover: proc(hovered: bool) = nil): Widget =
  Widget(kind: wkGestureDetector, gdChild: child, gdOnTap: onTap, gdOnHover: onHover)

proc scaffold*(body: Widget,
               appBar: AppBarConfig = AppBarConfig(),
               floatingAction: Widget = nil): Widget =
  Widget(kind: wkScaffold, scfBody: body, scfAppBar: appBar, scfFloatingAction: floatingAction)

proc sizedBox*(child: Widget = nil,
               width, height: int = -1): Widget =
  Widget(kind: wkSizedBox, swChild: child, swWidth: width, swHeight: height)

proc padding*(child: Widget, insets: Insets): Widget =
  Widget(kind: wkPadding, padChild: child, padInsets: insets)

proc align*(child: Widget, alignment: Alignment,
            width, height: int = -1): Widget =
  Widget(kind: wkAlign, alChild: child, alAlignment: alignment,
         alWidth: width, alHeight: height)

proc card*(child: Widget,
           padding: Insets = insets(16),
           margin: Insets = insets(4),
           radius: int = 12,
           color: Color = colBgCard): Widget =
  Widget(kind: wkCard, cardChild: child, cardPadding: padding,
         cardMargin: margin, cardRadius: radius, cardColor: color)

proc progressBar*(value: float,
                  height: int = 8,
                  color: Color = colBlue,
                  trackColor: Color = colBgFocus,
                  radius: int = 4): Widget =
  Widget(kind: wkProgressBar, pbValue: clamp(value, 0.0, 1.0),
         pbHeight: height, pbColor: color, pbTrackColor: trackColor,
         pbRadius: radius)

# =============================================================================
# Default font (shared across widgets)
# =============================================================================

var globalDefaultFont: Font

proc defaultFont*(): Font =
  if globalDefaultFont == nil:
    globalDefaultFont = loadFont("", 16)
  globalDefaultFont

proc setDefaultFont*(font: Font) =
  globalDefaultFont = font

# =============================================================================
# Layout Engine
# =============================================================================

proc defaultConstraints*(): LayoutConstraints =
  LayoutConstraints(minWidth: 0, maxWidth: 10000, minHeight: 0, maxHeight: 10000)

proc constrainedSize*(c: LayoutConstraints, w, h: int): LayoutSize =
  LayoutSize(
    width: clamp(w, c.minWidth, c.maxWidth),
    height: clamp(h, c.minHeight, c.maxHeight)
  )

proc measure*(widget: Widget, constraints: LayoutConstraints): LayoutSize =
  case widget.kind
  of wkContainer:
    var innerConstraints = constraints
    if widget.contWidth >= 0:
      innerConstraints.minWidth = widget.contWidth
      innerConstraints.maxWidth = widget.contWidth
    if widget.contHeight >= 0:
      innerConstraints.minHeight = widget.contHeight
      innerConstraints.maxHeight = widget.contHeight

    var childSize = LayoutSize(width: innerConstraints.minWidth, height: innerConstraints.minHeight)
    if widget.contChild != nil:
      childSize = widget.contChild.measure(innerConstraints)

    let padH = widget.contPadding.horizontal
    let padV = widget.contPadding.vertical
    let marginH = widget.contMargin.horizontal
    let marginV = widget.contMargin.vertical

    LayoutSize(
      width: clamp(childSize.width + padH, constraints.minWidth, constraints.maxWidth) + marginH,
      height: clamp(childSize.height + padV, constraints.minHeight, constraints.maxHeight) + marginV
    )

  of wkText:
    let (_, textH) = defaultFont().measureText(widget.txtContent)
    let textW = defaultFont().measureTextWidth(widget.txtContent)
    LayoutSize(
      width: clamp(textW, constraints.minWidth, constraints.maxWidth),
      height: clamp(textH, constraints.minHeight, constraints.maxHeight)
    )

  of wkRow:
    var totalW = 0
    var maxH = 0
    let childCount = widget.rowChildren.len
    for i, child in widget.rowChildren:
      let childConstraints = LayoutConstraints(
        minWidth: 0, maxWidth: constraints.maxWidth,
        minHeight: constraints.minHeight, maxHeight: constraints.maxHeight
      )
      let sz = child.measure(childConstraints)
      totalW += sz.width
      if i > 0: totalW += widget.rowSpacing
      maxH = max(maxH, sz.height)
    LayoutSize(
      width: clamp(totalW, constraints.minWidth, constraints.maxWidth),
      height: clamp(maxH, constraints.minHeight, constraints.maxHeight)
    )

  of wkColumn:
    var totalH = 0
    var maxW = 0
    let childCount = widget.colChildren.len
    for i, child in widget.colChildren:
      let childConstraints = LayoutConstraints(
        minWidth: constraints.minWidth, maxWidth: constraints.maxWidth,
        minHeight: 0, maxHeight: constraints.maxHeight - totalH
      )
      let sz = child.measure(childConstraints)
      maxW = max(maxW, sz.width)
      totalH += sz.height
      if i > 0: totalH += widget.colSpacing
    LayoutSize(
      width: clamp(maxW, constraints.minWidth, constraints.maxWidth),
      height: clamp(totalH, constraints.minHeight, constraints.maxHeight)
    )

  of wkStack:
    var maxW = 0
    var maxH = 0
    for child in widget.stkChildren:
      let sz = child.measure(constraints)
      maxW = max(maxW, sz.width)
      maxH = max(maxH, sz.height)
    LayoutSize(
      width: clamp(maxW, constraints.minWidth, constraints.maxWidth),
      height: clamp(maxH, constraints.minHeight, constraints.maxHeight)
    )

  of wkCenter:
    var innerConstraints = constraints
    if widget.centerWidth >= 0:
      innerConstraints.minWidth = widget.centerWidth
      innerConstraints.maxWidth = widget.centerWidth
    if widget.centerHeight >= 0:
      innerConstraints.minHeight = widget.centerHeight
      innerConstraints.maxHeight = widget.centerHeight

    var childSize = LayoutSize(width: 0, height: 0)
    if widget.centerChild != nil:
      childSize = widget.centerChild.measure(innerConstraints)

    LayoutSize(
      width: clamp(max(childSize.width, innerConstraints.minWidth), constraints.minWidth, constraints.maxWidth),
      height: clamp(max(childSize.height, innerConstraints.minHeight), constraints.minHeight, constraints.maxHeight)
    )

  of wkExpanded:
    if widget.expChild != nil:
      widget.expChild.measure(constraints)
    else:
      LayoutSize(width: 0, height: 0)

  of wkSpacer:
    LayoutSize(width: 0, height: 0)

  of wkButton:
    let (_, btnH) = defaultFont().measureText(widget.btnLabel)
    let btnW = defaultFont().measureTextWidth(widget.btnLabel) +
      widget.btnStyle.padding.horizontal + 16
    LayoutSize(
      width: clamp(btnW, constraints.minWidth, constraints.maxWidth),
      height: clamp(max(btnH + widget.btnStyle.padding.vertical, 36), constraints.minHeight, constraints.maxHeight)
    )

  of wkGestureDetector:
    if widget.gdChild != nil:
      widget.gdChild.measure(constraints)
    else:
      LayoutSize(width: 0, height: 0)

  of wkScaffold:
    let appBarH = widget.scfAppBar.height
    var bodyConstraints = constraints
    bodyConstraints.minHeight = max(0, bodyConstraints.minHeight - appBarH)
    bodyConstraints.maxHeight = max(0, bodyConstraints.maxHeight - appBarH)
    var bodySize = LayoutSize(width: constraints.minWidth, height: bodyConstraints.minHeight)
    if widget.scfBody != nil:
      bodySize = widget.scfBody.measure(bodyConstraints)
    LayoutSize(
      width: clamp(bodySize.width, constraints.minWidth, constraints.maxWidth),
      height: clamp(bodySize.height + appBarH, constraints.minHeight, constraints.maxHeight)
    )

  of wkSizedBox:
    let w = if widget.swWidth >= 0: widget.swWidth else: constraints.minWidth
    let h = if widget.swHeight >= 0: widget.swHeight else: constraints.minHeight
    if widget.swChild != nil:
      let childConstraints = LayoutConstraints(
        minWidth: 0, maxWidth: w,
        minHeight: 0, maxHeight: h
      )
      let childSize = widget.swChild.measure(childConstraints)
      LayoutSize(
        width: clamp(max(w, childSize.width), constraints.minWidth, constraints.maxWidth),
        height: clamp(max(h, childSize.height), constraints.minHeight, constraints.maxHeight)
      )
    else:
      LayoutSize(
        width: clamp(w, constraints.minWidth, constraints.maxWidth),
        height: clamp(h, constraints.minHeight, constraints.maxHeight)
      )

  of wkPadding:
    if widget.padChild != nil:
      let childConstraints = LayoutConstraints(
        minWidth: max(0, constraints.minWidth - widget.padInsets.horizontal),
        maxWidth: max(0, constraints.maxWidth - widget.padInsets.horizontal),
        minHeight: max(0, constraints.minHeight - widget.padInsets.vertical),
        maxHeight: max(0, constraints.maxHeight - widget.padInsets.vertical)
      )
      let childSize = widget.padChild.measure(childConstraints)
      LayoutSize(
        width: clamp(childSize.width + widget.padInsets.horizontal, constraints.minWidth, constraints.maxWidth),
        height: clamp(childSize.height + widget.padInsets.vertical, constraints.minHeight, constraints.maxHeight)
      )
    else:
      LayoutSize(
        width: clamp(widget.padInsets.horizontal, constraints.minWidth, constraints.maxWidth),
        height: clamp(widget.padInsets.vertical, constraints.minHeight, constraints.maxHeight)
      )

  of wkAlign:
    var innerW = if widget.alWidth >= 0: widget.alWidth else: constraints.maxWidth
    var innerH = if widget.alHeight >= 0: widget.alHeight else: constraints.maxHeight
    if widget.alChild != nil:
      let childSize = widget.alChild.measure(LayoutConstraints(
        minWidth: 0, maxWidth: innerW,
        minHeight: 0, maxHeight: innerH
      ))
      innerW = childSize.width
      innerH = childSize.height
    LayoutSize(
      width: clamp(max(innerW, widget.alWidth), constraints.minWidth, constraints.maxWidth),
      height: clamp(max(innerH, widget.alHeight), constraints.minHeight, constraints.maxHeight)
    )

  of wkCard:
    var innerConstraints = LayoutConstraints(
      minWidth: max(0, constraints.minWidth - widget.cardPadding.horizontal - widget.cardMargin.horizontal),
      maxWidth: max(0, constraints.maxWidth - widget.cardPadding.horizontal - widget.cardMargin.horizontal),
      minHeight: max(0, constraints.minHeight - widget.cardPadding.vertical - widget.cardMargin.vertical),
      maxHeight: max(0, constraints.maxHeight - widget.cardPadding.vertical - widget.cardMargin.vertical)
    )
    var childSize = LayoutSize(width: 0, height: 0)
    if widget.cardChild != nil:
      childSize = widget.cardChild.measure(innerConstraints)
    LayoutSize(
      width: clamp(childSize.width + widget.cardPadding.horizontal + widget.cardMargin.horizontal,
                   constraints.minWidth, constraints.maxWidth),
      height: clamp(childSize.height + widget.cardPadding.vertical + widget.cardMargin.vertical,
                    constraints.minHeight, constraints.maxHeight)
    )

  of wkProgressBar:
    LayoutSize(
      width: clamp(max(constraints.minWidth, 200), constraints.minWidth, constraints.maxWidth),
      height: clamp(widget.pbHeight, constraints.minHeight, constraints.maxHeight)
    )

  of wkImage:
    LayoutSize(
      width: clamp(widget.imgWidth, constraints.minWidth, constraints.maxWidth),
      height: clamp(widget.imgHeight, constraints.minHeight, constraints.maxHeight)
    )

# =============================================================================
# Render Engine
# =============================================================================

proc render*(widget: Widget, gc: GraphicsContext, x, y, width, height: int) =
  case widget.kind
  of wkContainer:
    let dec = widget.contDecoration
    # Draw background
    if dec.color.a > 0:
      if dec.borderRadius > 0:
        gc.fillRoundedRect(x, y, width, height, dec.borderRadius, dec.color)
      else:
        gc.fillRect(x, y, width, height, dec.color)

    # Draw gradient
    if dec.gradient.enabled:
      gc.fillGradientV(x, y, width, height, dec.gradient.topColor, dec.gradient.bottomColor)

    # Draw border
    if dec.border == bsSolid and dec.borderWidth > 0:
      if dec.borderRadius > 0:
        gc.drawRoundedRect(x, y, width, height, dec.borderRadius,
                          dec.borderColor, dec.borderWidth)
      else:
        for t in 0 ..< dec.borderWidth:
          gc.drawRect(x + t, y + t, width - 2*t, height - 2*t, dec.borderColor)

    # Render child
    if widget.contChild != nil:
      let innerW = max(0, width - widget.contPadding.horizontal)
      let innerH = max(0, height - widget.contPadding.vertical)
      let childMeasured = widget.contChild.measure(
        LayoutConstraints(maxWidth: innerW, maxHeight: innerH))
      let childMeasuredH = childMeasured.height
      let childMeasuredW = childMeasured.width

      let alignX = widget.contAlignment.x
      let alignY = widget.contAlignment.y
      let childX = widget.contPadding.left + int((innerW - childMeasuredW).float * (alignX + 1.0) / 2.0)
      let childY = widget.contPadding.top + int((innerH - childMeasuredH).float * (alignY + 1.0) / 2.0)

      widget.contChild.render(gc, x + childX, y + childY, innerW, innerH)

  of wkText:
    let font = defaultFont()
    gc.drawText(x, y, widget.txtContent, font, widget.txtStyle.color)

  of wkRow:
    let children = widget.rowChildren
    let spacing = widget.rowSpacing
    let childCount = children.len

    # Calculate total width and max height
    var sizes: seq[LayoutSize]
    var totalW = 0
    var maxH = 0
    for child in children:
      let sz = child.measure(LayoutConstraints(
        maxWidth: width, maxHeight: height))
      sizes.add(sz)
      totalW += sz.width
      maxH = max(maxH, sz.height)
    totalW += spacing * max(0, childCount - 1)

    # Calculate starting X based on mainAxisAlignment
    var startX = x
    case widget.rowMainAlign
    of msaStart: discard
    of msaEnd: startX = x + max(0, width - totalW)
    of msaCenter: startX = x + max(0, (width - totalW) div 2)
    of msaSpaceBetween:
      if childCount > 1:
        let gap = max(0, (width - totalW) div (childCount - 1))
        startX = x  # handled in loop
    of msaSpaceAround:
      let gap = if childCount > 0: max(0, width - totalW) div childCount else: 0
      startX = x + gap div 2
    of msaSpaceEvenly:
      let gap = if childCount > 0: max(0, width - totalW) div (childCount + 1) else: 0
      startX = x + gap

    # Render children
    var cx = startX
    for i, child in children:
      # Calculate Y based on crossAxisAlignment
      var cy = y
      case widget.rowCrossAlign
      of csaStart: discard
      of csaEnd: cy = y + max(0, height - sizes[i].height)
      of csaCenter: cy = y + max(0, (height - sizes[i].height) div 2)
      of csaStretch: discard

      child.render(gc, cx, cy, sizes[i].width, max(sizes[i].height, height))
      cx += sizes[i].width + spacing

      if widget.rowMainAlign == msaSpaceBetween and childCount > 1:
        let gap = max(0, (width - totalW) div (childCount - 1))
        cx += gap - spacing

  of wkColumn:
    let children = widget.colChildren
    let spacing = widget.colSpacing
    let childCount = children.len

    var sizes: seq[LayoutSize]
    var totalH = 0
    var maxW = 0
    for child in children:
      let sz = child.measure(LayoutConstraints(
        maxWidth: width, maxHeight: height - totalH))
      sizes.add(sz)
      totalH += sz.height
      maxW = max(maxW, sz.width)
      totalH += spacing
    if childCount > 0: totalH -= spacing

    var startY = y
    case widget.colMainAlign
    of msaStart: discard
    of msaEnd: startY = y + max(0, height - totalH)
    of msaCenter: startY = y + max(0, (height - totalH) div 2)
    of msaSpaceBetween:
      if childCount > 1:
        let gap = max(0, (height - totalH) div (childCount - 1))
        startY = y
    of msaSpaceAround:
      let gap = if childCount > 0: max(0, height - totalH) div childCount else: 0
      startY = y + gap div 2
    of msaSpaceEvenly:
      let gap = if childCount > 0: max(0, height - totalH) div (childCount + 1) else: 0
      startY = y + gap

    var cy = startY
    for i, child in children:
      var cx = x
      case widget.colCrossAlign
      of csaStart: discard
      of csaEnd: cx = x + max(0, width - sizes[i].width)
      of csaCenter: cx = x + max(0, (width - sizes[i].width) div 2)
      of csaStretch: discard

      child.render(gc, cx, cy, max(sizes[i].width, width), sizes[i].height)
      cy += sizes[i].height + spacing

      if widget.colMainAlign == msaSpaceBetween and childCount > 1:
        let gap = max(0, (height - totalH) div (childCount - 1))
        cy += gap - spacing

  of wkStack:
    for child in widget.stkChildren:
      child.render(gc, x, y, width, height)

  of wkCenter:
    if widget.centerChild != nil:
      let childSize = widget.centerChild.measure(
        LayoutConstraints(maxWidth: width, maxHeight: height))
      let ox = (width - childSize.width) div 2
      let oy = (height - childSize.height) div 2
      widget.centerChild.render(gc, x + ox, y + oy, childSize.width, childSize.height)

  of wkExpanded:
    if widget.expChild != nil:
      widget.expChild.render(gc, x, y, width, height)

  of wkSpacer:
    discard

  of wkButton:
    let btnStyle = widget.btnStyle
    let btnW = width
    let btnH = height

    # Button background
    if btnStyle.borderRadius > 0:
      gc.fillRoundedRect(x, y, btnW, btnH, btnStyle.borderRadius, btnStyle.backgroundColor)
    else:
      gc.fillRect(x, y, btnW, btnH, btnStyle.backgroundColor)

    # Button text
    let font = defaultFont()
    let (_, textH) = font.measureText(widget.btnLabel)
    let textW = font.measureTextWidth(widget.btnLabel)
    let tx = x + (btnW - textW) div 2
    let ty = y + (btnH - textH) div 2
    gc.drawText(tx, ty, widget.btnLabel, font, btnStyle.foregroundColor)

  of wkGestureDetector:
    if widget.gdChild != nil:
      widget.gdChild.render(gc, x, y, width, height)

  of wkScaffold:
    # App bar
    let appBarH = widget.scfAppBar.height
    if appBarH > 0:
      gc.fillRect(x, y, width, appBarH, widget.scfAppBar.bgColor)
      let font = defaultFont()
      let (_, th) = font.measureText(widget.scfAppBar.title)
      let tw = font.measureTextWidth(widget.scfAppBar.title)
      gc.drawText(x + 16, y + (appBarH - th) div 2,
                  widget.scfAppBar.title, font, widget.scfAppBar.fgColor)

    # Body
    if widget.scfBody != nil:
      widget.scfBody.render(gc, x, y + appBarH, width, max(0, height - appBarH))

  of wkSizedBox:
    if widget.swChild != nil:
      let w = if widget.swWidth >= 0: widget.swWidth else: width
      let h = if widget.swHeight >= 0: widget.swHeight else: height
      widget.swChild.render(gc, x, y, w, h)

  of wkPadding:
    if widget.padChild != nil:
      widget.padChild.render(gc, x + widget.padInsets.left, y + widget.padInsets.top,
                             max(0, width - widget.padInsets.horizontal),
                             max(0, height - widget.padInsets.vertical))

  of wkAlign:
    if widget.alChild != nil:
      let childSize = widget.alChild.measure(
        LayoutConstraints(maxWidth: width, maxHeight: height))
      let ox = int((width - childSize.width).float * (widget.alAlignment.x + 1.0) / 2.0)
      let oy = int((height - childSize.height).float * (widget.alAlignment.y + 1.0) / 2.0)
      widget.alChild.render(gc, x + ox, y + oy, childSize.width, childSize.height)

  of wkCard:
    # Card shadow (simple)
    if widget.cardMargin.top > 0 or widget.cardMargin.left > 0:
      let shadowOffset = 2
      gc.fillRoundedRect(
        x + widget.cardMargin.left + shadowOffset,
        y + widget.cardMargin.top + shadowOffset,
        width - widget.cardMargin.horizontal,
        height - widget.cardMargin.vertical,
        widget.cardRadius, rgba(0, 0, 0, 40))

    # Card background
    gc.fillRoundedRect(
      x + widget.cardMargin.left,
      y + widget.cardMargin.top,
      width - widget.cardMargin.horizontal,
      height - widget.cardMargin.vertical,
      widget.cardRadius, widget.cardColor)

    # Card child
    if widget.cardChild != nil:
      let innerX = x + widget.cardMargin.left + widget.cardPadding.left
      let innerY = y + widget.cardMargin.top + widget.cardPadding.top
      let innerW = max(0, width - widget.cardMargin.horizontal - widget.cardPadding.horizontal)
      let innerH = max(0, height - widget.cardMargin.vertical - widget.cardPadding.vertical)
      widget.cardChild.render(gc, innerX, innerY, innerW, innerH)

  of wkProgressBar:
    # Track
    if widget.pbRadius > 0:
      gc.fillRoundedRect(x, y, width, widget.pbHeight, widget.pbRadius, widget.pbTrackColor)
    else:
      gc.fillRect(x, y, width, widget.pbHeight, widget.pbTrackColor)

    # Fill
    let fillW = int(widget.pbValue.float * width.float)
    if fillW > 0:
      if widget.pbRadius > 0:
        gc.fillRoundedRect(x, y, fillW, widget.pbHeight, widget.pbRadius, widget.pbColor)
      else:
        gc.fillRect(x, y, fillW, widget.pbHeight, widget.pbColor)

  of wkImage:
    if widget.imgData.len == widget.imgWidth * widget.imgHeight:
      for row in 0 ..< widget.imgHeight:
        for col in 0 ..< widget.imgWidth:
          let px = widget.imgData[row * widget.imgWidth + col]
          if ((px shr 24) and 0xFF'u32) > 0'u32:
            gc.buffer.pixels[(y + row) * gc.buffer.width + (x + col)] = px

# =============================================================================
# Hit testing (for event handling)
# =============================================================================

proc hitTest*(widget: Widget, px, py, x, y, width, height: int): HitTestResult =
  result = HitTestResult(hit: false)

  if px < x or px >= x + width or py < y or py >= y + height:
    return result

  case widget.kind
  of wkContainer:
    result = HitTestResult(hit: true, x: px - x, y: py - y)
    if widget.contChild != nil:
      let childResult = widget.contChild.hitTest(px, py,
        x + widget.contPadding.left, y + widget.contPadding.top,
        max(0, width - widget.contPadding.horizontal),
        max(0, height - widget.contPadding.vertical))
      if childResult.hit:
        return childResult

  of wkButton:
    result = HitTestResult(hit: true, x: px - x, y: py - y)

  of wkGestureDetector:
    result = HitTestResult(hit: true, x: px - x, y: py - y)
    if widget.gdChild != nil:
      let childResult = widget.gdChild.hitTest(px, py, x, y, width, height)
      if childResult.hit:
        return childResult

  of wkRow, wkColumn:
    result = HitTestResult(hit: true, x: px - x, y: py - y)

  of wkStack:
    # Check children in reverse order (topmost first)
    for i in countdown(widget.stkChildren.len - 1, 0):
      let childResult = widget.stkChildren[i].hitTest(px, py, x, y, width, height)
      if childResult.hit:
        return childResult
    result = HitTestResult(hit: true, x: px - x, y: py - y)

  of wkCard:
    result = HitTestResult(hit: true, x: px - x, y: py - y)
    if widget.cardChild != nil:
      let childResult = widget.cardChild.hitTest(px, py,
        x + widget.cardMargin.left + widget.cardPadding.left,
        y + widget.cardMargin.top + widget.cardPadding.top,
        max(0, width - widget.cardMargin.horizontal - widget.cardPadding.horizontal),
        max(0, height - widget.cardMargin.vertical - widget.cardPadding.vertical))
      if childResult.hit:
        return childResult

  of wkScaffold:
    if widget.scfBody != nil:
      let appBarH = widget.scfAppBar.height
      let bodyResult = widget.scfBody.hitTest(px, py, x, y + appBarH, width, max(0, height - appBarH))
      if bodyResult.hit:
        return bodyResult
    result = HitTestResult(hit: true, x: px - x, y: py - y)

  of wkCenter, wkExpanded, wkSizedBox, wkPadding, wkAlign:
    result = HitTestResult(hit: true, x: px - x, y: py - y)

  else:
    result = HitTestResult(hit: true, x: px - x, y: py - y)
