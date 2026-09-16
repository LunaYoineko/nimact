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

import std/strutils
import std/sequtils
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
    wkProgressBar, wkImage,
    wkDivider, wkCheckbox, wkSwitch, wkSlider, wkTextField

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
    of wkDivider:
      divThickness*: int
      divColor*: Color
      divVertical*: bool
    of wkCheckbox:
      chkValue*: bool
      chkOnChanged*: proc(checked: bool)
      chkLabel*: string
      chkActiveColor*: Color
      chkCheckColor*: Color
    of wkSwitch:
      swValue*: bool
      swOnChanged*: proc(value: bool)
      swActiveColor*: Color
      swThumbColor*: Color
      swTrackColor*: Color
    of wkSlider:
      sldValue*: float
      sldMin*, sldMax*: float
      sldOnChanged*: proc(value: float)
      sldActiveColor*: Color
      sldThumbColor*: Color
      sldTrackColor*: Color
      sldThumbRadius*: int
    of wkTextField:
      tfText*: string
      tfOnChanged*: proc(text: string)
      tfOnSubmitted*: proc(text: string)
      tfPlaceholder*: string
      tfStyle*: TextStyle
      tfMaxLines*: int
      tfMaxLength*: int
      tfObscureText*: bool
      tfReadOnly*: bool
      tfFocused*: bool

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

proc divider*(thickness: int = 1,
              color: Color = colTextMuted,
              vertical: bool = false): Widget =
  Widget(kind: wkDivider, divThickness: thickness, divColor: color, divVertical: vertical)

proc checkbox*(value: bool = false,
               onChanged: proc(checked: bool) = nil,
               label: string = "",
               activeColor: Color = colBlue,
               checkColor: Color = colWhite): Widget =
  Widget(kind: wkCheckbox, chkValue: value, chkOnChanged: onChanged,
         chkLabel: label, chkActiveColor: activeColor, chkCheckColor: checkColor)

proc switch*(value: bool = false,
             onChanged: proc(value: bool) = nil,
             activeColor: Color = colBlue,
             thumbColor: Color = colWhite,
             trackColor: Color = colBgFocus): Widget =
  Widget(kind: wkSwitch, swValue: value, swOnChanged: onChanged,
         swActiveColor: activeColor, swThumbColor: thumbColor, swTrackColor: trackColor)

proc slider*(value: float = 0.0,
             min: float = 0.0,
             max: float = 1.0,
             onChanged: proc(value: float) = nil,
             activeColor: Color = colBlue,
             thumbColor: Color = colWhite,
             trackColor: Color = colBgFocus,
             thumbRadius: int = 12): Widget =
  Widget(kind: wkSlider, sldValue: clamp(value, min, max), sldMin: min, sldMax: max,
         sldOnChanged: onChanged, sldActiveColor: activeColor,
         sldThumbColor: thumbColor, sldTrackColor: trackColor,
         sldThumbRadius: thumbRadius)

proc textField*(text: string = "",
                onChanged: proc(text: string) = nil,
                onSubmitted: proc(text: string) = nil,
                placeholder: string = "",
                style: TextStyle = textStyle(),
                maxLines: int = 1,
                maxLength: int = -1,
                obscureText: bool = false,
                readOnly: bool = false): Widget =
  Widget(kind: wkTextField, tfText: text, tfOnChanged: onChanged,
         tfOnSubmitted: onSubmitted, tfPlaceholder: placeholder,
         tfStyle: style, tfMaxLines: maxLines, tfMaxLength: maxLength,
         tfObscureText: obscureText, tfReadOnly: readOnly, tfFocused: false)

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
    # Two-pass flex layout for Row
    var children = widget.rowChildren
    let spacing = widget.rowSpacing
    let childCount = children.len
    
    # First pass: measure non-Expanded children
    var totalFixedW = 0
    var maxH = 0
    var totalFlex = 0
    var expandedIndices: seq[int] = @[]
    var expandedFlexes: seq[int] = @[]
    
    var sizes: seq[LayoutSize] = newSeq[LayoutSize](childCount)
    
    for i, child in children:
      if child.kind == wkExpanded:
        totalFlex += child.expFlex
        expandedIndices.add(i)
        expandedFlexes.add(child.expFlex)
      else:
        let sz = child.measure(LayoutConstraints(
          minWidth: 0, maxWidth: constraints.maxWidth,
          minHeight: constraints.minHeight, maxHeight: constraints.maxHeight
        ))
        sizes[i] = sz
        totalFixedW += sz.width
        maxH = max(maxH, sz.height)
    
    totalFixedW += spacing * max(0, childCount - 1)
    
    # Calculate available space for Expanded children
    let availableW = max(0, constraints.maxWidth - totalFixedW)
    var flexUnit = 0
    if totalFlex > 0:
      flexUnit = availableW div totalFlex
    
    # Second pass: measure Expanded children with allocated space
    for idx, i in expandedIndices:
      let child = children[i]
      let allocatedW = flexUnit * expandedFlexes[idx]
      if child.expChild != nil:
        let childConstraints = LayoutConstraints(
          minWidth: allocatedW, maxWidth: allocatedW,
          minHeight: constraints.minHeight, maxHeight: constraints.maxHeight
        )
        let sz = child.expChild.measure(childConstraints)
        sizes[i] = sz
        maxH = max(maxH, sz.height)
      else:
        sizes[i] = LayoutSize(width: allocatedW, height: 0)
    
    let totalW = totalFixedW + availableW
    LayoutSize(
      width: clamp(totalW, constraints.minWidth, constraints.maxWidth),
      height: clamp(maxH, constraints.minHeight, constraints.maxHeight)
    )

  of wkColumn:
    # Two-pass flex layout for Column
    var children = widget.colChildren
    let spacing = widget.colSpacing
    let childCount = children.len
    
    # First pass: measure non-Expanded children
    var totalFixedH = 0
    var maxW = 0
    var totalFlex = 0
    var expandedIndices: seq[int] = @[]
    var expandedFlexes: seq[int] = @[]
    
    var sizes: seq[LayoutSize] = newSeq[LayoutSize](childCount)
    
    for i, child in children:
      if child.kind == wkExpanded:
        totalFlex += child.expFlex
        expandedIndices.add(i)
        expandedFlexes.add(child.expFlex)
      else:
        let sz = child.measure(LayoutConstraints(
          minWidth: constraints.minWidth, maxWidth: constraints.maxWidth,
          minHeight: 0, maxHeight: constraints.maxHeight
        ))
        sizes[i] = sz
        totalFixedH += sz.height
        maxW = max(maxW, sz.width)
    
    totalFixedH += spacing * max(0, childCount - 1)
    
    # Calculate available space for Expanded children
    let availableH = max(0, constraints.maxHeight - totalFixedH)
    var flexUnit = 0
    if totalFlex > 0:
      flexUnit = availableH div totalFlex
    
    # Second pass: measure Expanded children with allocated space
    for idx, i in expandedIndices:
      let child = children[i]
      let allocatedH = flexUnit * expandedFlexes[idx]
      if child.expChild != nil:
        let childConstraints = LayoutConstraints(
          minWidth: constraints.minWidth, maxWidth: constraints.maxWidth,
          minHeight: allocatedH, maxHeight: allocatedH
        )
        let sz = child.expChild.measure(childConstraints)
        sizes[i] = sz
        maxW = max(maxW, sz.width)
      else:
        sizes[i] = LayoutSize(width: 0, height: allocatedH)
    
    let totalH = totalFixedH + availableH
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

  of wkDivider:
    if widget.divVertical:
      LayoutSize(
        width: clamp(widget.divThickness, constraints.minWidth, constraints.maxWidth),
        height: clamp(max(constraints.minHeight, 20), constraints.minHeight, constraints.maxHeight)
      )
    else:
      LayoutSize(
        width: clamp(max(constraints.minWidth, 100), constraints.minWidth, constraints.maxWidth),
        height: clamp(widget.divThickness, constraints.minHeight, constraints.maxHeight)
      )

  of wkCheckbox:
    let font = defaultFont()
    let (_, textH) = font.measureText(widget.chkLabel)
    let textW = font.measureTextWidth(widget.chkLabel)
    let boxSize = 24
    LayoutSize(
      width: clamp(boxSize + 8 + textW, constraints.minWidth, constraints.maxWidth),
      height: clamp(max(boxSize, textH), constraints.minHeight, constraints.maxHeight)
    )

  of wkSwitch:
    LayoutSize(
      width: clamp(56, constraints.minWidth, constraints.maxWidth),
      height: clamp(32, constraints.minHeight, constraints.maxHeight)
    )

  of wkSlider:
    LayoutSize(
      width: clamp(max(constraints.minWidth, 200), constraints.minWidth, constraints.maxWidth),
      height: clamp(max(48, widget.sldThumbRadius * 2 + 8), constraints.minHeight, constraints.maxHeight)
    )

  of wkTextField:
    let font = defaultFont()
    let (_, textH) = font.measureText("Ay")
    let lineH = textH + 4
    let tfHeight = lineH * widget.tfMaxLines + 16
    LayoutSize(
      width: clamp(max(constraints.minWidth, 200), constraints.minWidth, constraints.maxWidth),
      height: clamp(tfHeight, constraints.minHeight, constraints.maxHeight)
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
    
    # Two-pass flex layout (same as measure)
    var totalFixedW = 0
    var maxH = 0
    var totalFlex = 0
    var expandedIndices: seq[int] = @[]
    var expandedFlexes: seq[int] = @[]
    
    var sizes: seq[LayoutSize] = newSeq[LayoutSize](childCount)
    
    for i, child in children:
      if child.kind == wkExpanded:
        totalFlex += child.expFlex
        expandedIndices.add(i)
        expandedFlexes.add(child.expFlex)
      else:
        let sz = child.measure(LayoutConstraints(
          minWidth: 0, maxWidth: width,
          minHeight: 0, maxHeight: height
        ))
        sizes[i] = sz
        totalFixedW += sz.width
        maxH = max(maxH, sz.height)
    
    totalFixedW += spacing * max(0, childCount - 1)
    
    # Calculate available space for Expanded children
    let availableW = max(0, width - totalFixedW)
    var flexUnit = 0
    if totalFlex > 0:
      flexUnit = availableW div totalFlex
    
    # Second pass: measure Expanded children with allocated space
    for idx, i in expandedIndices:
      let child = children[i]
      let allocatedW = flexUnit * expandedFlexes[idx]
      if child.expChild != nil:
        let childConstraints = LayoutConstraints(
          minWidth: allocatedW, maxWidth: allocatedW,
          minHeight: 0, maxHeight: height
        )
        let sz = child.expChild.measure(childConstraints)
        sizes[i] = sz
        maxH = max(maxH, sz.height)
      else:
        sizes[i] = LayoutSize(width: allocatedW, height: 0)
    
    let totalW = totalFixedW + availableW
    
    # Calculate starting X based on mainAxisAlignment
    var startX = x
    case widget.rowMainAlign
    of msaStart: discard
    of msaEnd: startX = x + max(0, width - totalW)
    of msaCenter: startX = x + max(0, (width - totalW) div 2)
    of msaSpaceBetween:
      if childCount > 1:
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
      var childHeight = sizes[i].height
      case widget.rowCrossAlign
      of csaStart: discard
      of csaEnd: cy = y + max(0, height - sizes[i].height)
      of csaCenter: cy = y + max(0, (height - sizes[i].height) div 2)
      of csaStretch: cy = y; childHeight = height

      child.render(gc, cx, cy, sizes[i].width, childHeight)
      cx += sizes[i].width + spacing

      if widget.rowMainAlign == msaSpaceBetween and childCount > 1:
        let gap = max(0, (width - totalW) div (childCount - 1))
        cx += gap - spacing

  of wkColumn:
    let children = widget.colChildren
    let spacing = widget.colSpacing
    let childCount = children.len
    
    # Two-pass flex layout (same as measure)
    var totalFixedH = 0
    var maxW = 0
    var totalFlex = 0
    var expandedIndices: seq[int] = @[]
    var expandedFlexes: seq[int] = @[]
    
    var sizes: seq[LayoutSize] = newSeq[LayoutSize](childCount)
    
    for i, child in children:
      if child.kind == wkExpanded:
        totalFlex += child.expFlex
        expandedIndices.add(i)
        expandedFlexes.add(child.expFlex)
      else:
        let sz = child.measure(LayoutConstraints(
          minWidth: 0, maxWidth: width,
          minHeight: 0, maxHeight: height
        ))
        sizes[i] = sz
        totalFixedH += sz.height
        maxW = max(maxW, sz.width)
    
    totalFixedH += spacing * max(0, childCount - 1)
    
    # Calculate available space for Expanded children
    let availableH = max(0, height - totalFixedH)
    var flexUnit = 0
    if totalFlex > 0:
      flexUnit = availableH div totalFlex
    
    # Second pass: measure Expanded children with allocated space
    for idx, i in expandedIndices:
      let child = children[i]
      let allocatedH = flexUnit * expandedFlexes[idx]
      if child.expChild != nil:
        let childConstraints = LayoutConstraints(
          minWidth: 0, maxWidth: width,
          minHeight: allocatedH, maxHeight: allocatedH
        )
        let sz = child.expChild.measure(childConstraints)
        sizes[i] = sz
        maxW = max(maxW, sz.width)
      else:
        sizes[i] = LayoutSize(width: 0, height: allocatedH)
    
    let totalH = totalFixedH + availableH
    
    var startY = y
    case widget.colMainAlign
    of msaStart: discard
    of msaEnd: startY = y + max(0, height - totalH)
    of msaCenter: startY = y + max(0, (height - totalH) div 2)
    of msaSpaceBetween:
      if childCount > 1:
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
      var childWidth = sizes[i].width
      case widget.colCrossAlign
      of csaStart: discard
      of csaEnd: cx = x + max(0, width - sizes[i].width)
      of csaCenter: cx = x + max(0, (width - sizes[i].width) div 2)
      of csaStretch: cx = x; childWidth = width

      child.render(gc, cx, cy, childWidth, sizes[i].height)
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

  of wkDivider:
    if widget.divVertical:
      gc.fillRect(x, y, widget.divThickness, height, widget.divColor)
    else:
      gc.fillRect(x, y, width, widget.divThickness, widget.divColor)

  of wkCheckbox:
    let font = defaultFont()
    let boxSize = 24
    let boxX = x
    let boxY = y + (height - boxSize) div 2

    # Checkbox box
    if widget.chkValue:
      gc.fillRoundedRect(boxX, boxY, boxSize, boxSize, 4, widget.chkActiveColor)
      # Check mark
      let checkX = boxX + boxSize div 3
      let checkY = boxY + boxSize div 3
      let checkW = boxSize div 3
      let checkH = boxSize div 3 * 2
      gc.drawLine(checkX, checkY + checkH div 2, checkX + checkW div 2, checkY + checkH, widget.chkCheckColor, 2)
      gc.drawLine(checkX + checkW div 2, checkY + checkH, checkX + checkW, checkY, widget.chkCheckColor, 2)
    else:
      gc.drawRoundedRect(boxX, boxY, boxSize, boxSize, 4, widget.chkActiveColor, 2)

    # Label
    if widget.chkLabel.len > 0:
      gc.drawText(boxX + boxSize + 8, y + (height - font.measureTextHeight(widget.chkLabel)) div 2,
                  widget.chkLabel, font, colText)

  of wkSwitch:
    let trackW = 56
    let trackH = 32
    let trackX = x + (width - trackW) div 2
    let trackY = y + (height - trackH) div 2
    let thumbR = 14
    let thumbOffset = (widget.swValue.float * (trackW - thumbR * 2 - 4).float).int
    let thumbX = trackX + 2 + thumbOffset
    let thumbY = trackY + (trackH - thumbR * 2) div 2

    # Track
    if widget.swValue:
      gc.fillRoundedRect(trackX, trackY, trackW, trackH, trackH div 2, widget.swActiveColor)
    else:
      gc.fillRoundedRect(trackX, trackY, trackW, trackH, trackH div 2, widget.swTrackColor)

    # Thumb
    gc.fillCircle(thumbX + thumbR, thumbY + thumbR, thumbR, widget.swThumbColor)

  of wkSlider:
    let trackH = 4
    let trackY = y + (height - trackH) div 2
    let trackX = x
    let trackW = width
    let thumbR = widget.sldThumbRadius
    let valueRatio = (widget.sldValue - widget.sldMin) / (widget.sldMax - widget.sldMin)
    let thumbCX = trackX + int(valueRatio.float * (trackW - 1).float)
    let thumbCY = trackY + trackH div 2

    # Track
    gc.fillRoundedRect(trackX, trackY, trackW, trackH, trackH div 2, widget.sldTrackColor)
    # Active track portion
    let activeW = thumbCX - trackX
    if activeW > 0:
      gc.fillRoundedRect(trackX, trackY, activeW, trackH, trackH div 2, widget.sldActiveColor)

    # Thumb
    gc.fillCircle(thumbCX, thumbCY, thumbR, widget.sldThumbColor)
    gc.drawCircle(thumbCX, thumbCY, thumbR, colTextMuted, 1)

    # Value label
    let font = defaultFont()
    let valueStr = $widget.sldValue.formatFloat(ffDecimal, 2)
    let (_, textH) = font.measureText(valueStr)
    let textW = font.measureTextWidth(valueStr)
    gc.drawText(thumbCX - textW div 2, trackY - textH - 4, valueStr, font, colTextMuted)

  of wkTextField:
    let font = defaultFont()
    let padding = 8
    let fieldH = height
    let fieldW = width

    # Background
    if widget.tfFocused:
      gc.fillRoundedRect(x, y, fieldW, fieldH, 6, colBgFocus)
      gc.drawRoundedRect(x, y, fieldW, fieldH, 6, colBlue, 2)
    else:
      gc.fillRoundedRect(x, y, fieldW, fieldH, 6, colBgCard)
      gc.drawRoundedRect(x, y, fieldW, fieldH, 6, colBgHover, 1)

    # Text or placeholder
    let displayText = if widget.tfObscureText:
                        newString(widget.tfText.len).mapIt("●").join("")
                      else:
                        widget.tfText
    let isEmpty = displayText.len == 0 and widget.tfText.len == 0
    let textColor = if isEmpty: colTextMuted else: widget.tfStyle.color
    let textToDraw = if isEmpty: widget.tfPlaceholder else: displayText

    if textToDraw.len > 0:
      let (_, textH) = font.measureText(textToDraw)
      gc.drawText(x + padding, y + (fieldH - textH) div 2, textToDraw, font, textColor)

    # Cursor (when focused)
    if widget.tfFocused and not widget.tfReadOnly:
      let cursorX = x + padding + font.measureTextWidth(displayText)
      let (_, textH) = font.measureText("Ay")
      gc.drawLine(cursorX, y + (fieldH - textH) div 2,
                  cursorX, y + (fieldH + textH) div 2, colBlue, 2)

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

  of wkCenter, wkExpanded, wkSizedBox, wkPadding, wkAlign, wkDivider:
    result = HitTestResult(hit: true, x: px - x, y: py - y)

  of wkCheckbox, wkSwitch, wkSlider:
    result = HitTestResult(hit: true, x: px - x, y: py - y)

  of wkTextField:
    result = HitTestResult(hit: true, x: px - x, y: py - y)

  else:
    result = HitTestResult(hit: true, x: px - x, y: py - y)
