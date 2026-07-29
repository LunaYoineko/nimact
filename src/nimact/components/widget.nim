## =============================================================================
## nimact/components/widget.nim
## Widget tree structure for UI components:
##   - Widget: UI component tree definition
##   - Builder procs: helper functions to create each component
##   - measure: calculate widget sizes (layout)
##   - render: draw widgets into a buffer
##
## Widget types:
##   - Label:      text display
##   - VBox:       vertical layout (children stacked top to bottom)
##   - HBox:       horizontal layout (children arranged left to right)
##   - Center:     centered box
##   - Header:     full-width bar at top of screen
##   - Footer:     full-width bar at bottom of screen
##   - Progress:   progress bar
##   - Separator:  horizontal divider line
##   - Spacer:     empty space
##
## Layout mechanism:
##   1. measure() recursively computes required size for each widget
##   2. render() draws into the buffer based on computed sizes and positions
##   3. Parent widgets (VBox, HBox, etc.) calculate child placement
##
## Note: varargs cannot use do-block notation (Nim limitation)
##       Correct call form: vbox(label("a"), label("b"))
## =============================================================================

import std/unicode  # runeLen for Unicode string width calculation
import ../core/buffer

# =============================================================================
# Widget type definitions
# =============================================================================

type
  ## Discriminant enum for widget variant object
  WidgetKind* = enum
    wkLabel,      ## text label
    wkBox,        ## bordered box panel
    wkVBox,       ## vertical container
    wkHBox,       ## horizontal container
    wkCenter,     ## centered box
    wkHeader,     ## header bar (full-width)
    wkFooter,     ## footer bar (full-width)
    wkProgress,   ## progress bar
    wkSeparator,  ## horizontal divider
    wkSpacer      ## empty space

  ## Widget variant object
  ## Fields vary based on `kind`:
  ##   wkLabel     -> labelText, labelStyle
  ##   wkVBox/HBox -> children, gap
  ##   wkCenter    -> centerW, centerH, centerChildren
  ##   wkHeader/F  -> barText, barStyle
  ##   wkProgress  -> progressValue, progressMax, progressStyle
  ##   wkSeparator -> sepStyle
  ##   wkSpacer    -> spacerHeight
  Widget* = ref object
    case kind*: WidgetKind
    of wkLabel:
      labelText*: string
      labelStyle*: Style
    of wkBox:
      boxW*, boxH*: int
      boxStyle*: Style
      boxBorder*: BorderStyle
      boxChildren*: seq[Widget]
    of wkVBox, wkHBox:
      children*: seq[Widget]
      gap*: int
      vhboxStyle*: Style
    of wkCenter:
      centerW*, centerH*: int
      centerChildren*: seq[Widget]
    of wkHeader, wkFooter:
      barText*: string
      barStyle*: Style
    of wkProgress:
      progressValue*: float
      progressMax*: float
      progressStyle*: Style
    of wkSeparator:
      sepStyle*: Style
    of wkSpacer:
      spacerHeight*: int

# =============================================================================
# Builder functions
# =============================================================================

proc label*(text: string, fg: Color = defaultColor(),
            bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkLabel, labelText: text, labelStyle: style(fg, bg, bold))

proc box*(w, h: int, style: Style = style(fg = colBlue),
          borderType: BorderStyle = bsRounded,
          children: varargs[Widget]): Widget =
  Widget(kind: wkBox, boxW: w, boxH: h, boxStyle: style,
          boxBorder: borderType, boxChildren: @children)

proc vbox*(children: varargs[Widget]): Widget =
  Widget(kind: wkVBox, children: @children, gap: 0, vhboxStyle: style())

proc vbox*(gap: int, children: varargs[Widget]): Widget =
  Widget(kind: wkVBox, children: @children, gap: gap, vhboxStyle: style())

proc vbox*(gap: int, style: Style, children: varargs[Widget]): Widget =
  Widget(kind: wkVBox, children: @children, gap: gap, vhboxStyle: style)

proc vbox*(style: Style, children: varargs[Widget]): Widget =
  Widget(kind: wkVBox, children: @children, gap: 0, vhboxStyle: style)

proc hbox*(children: varargs[Widget]): Widget =
  Widget(kind: wkHBox, children: @children, gap: 0, vhboxStyle: style())

proc hbox*(gap: int, children: varargs[Widget]): Widget =
  Widget(kind: wkHBox, children: @children, gap: gap, vhboxStyle: style())

proc hbox*(gap: int, style: Style, children: varargs[Widget]): Widget =
  Widget(kind: wkHBox, children: @children, gap: gap, vhboxStyle: style)

proc hbox*(style: Style, children: varargs[Widget]): Widget =
  Widget(kind: wkHBox, children: @children, gap: 0, vhboxStyle: style)

proc center*(w, h: int, children: varargs[Widget]): Widget =
  Widget(kind: wkCenter, centerW: w, centerH: h, centerChildren: @children)

proc header*(text: string, fg: Color = defaultColor(),
             bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkHeader, barText: text, barStyle: style(fg, bg, bold))

proc footer*(text: string, fg: Color = defaultColor(),
             bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkFooter, barText: text, barStyle: style(fg, bg, bold))

proc progress*(value: float, max: float = 1.0,
               fg: Color = defaultColor(), bg: Color = defaultColor()): Widget =
  Widget(kind: wkProgress, progressValue: value, progressMax: max,
         progressStyle: style(fg, bg))

proc separator*(fg: Color = defaultColor(), bg: Color = defaultColor()): Widget =
  Widget(kind: wkSeparator, sepStyle: style(fg, bg))

proc spacer*(height: int = 1): Widget =
  Widget(kind: wkSpacer, spacerHeight: height)
  
# =============================================================================
# Size calculation (measure)
# =============================================================================

proc stringWidth(s: string): int =
  for r in s.runes:
      result += runeWidth(r)

## Compute required size (width, height) for a widget.
## availableWidth: width passed from parent
## Returns: (required width, required height)
proc measure*(w: Widget, availableWidth: int): (int, int) =
  case w.kind
  of wkLabel:
    let wCount = stringWidth(w.labelText)
    (wCount, 1)
  of wkBox:
    (w.boxW, w.boxH)
  of wkVBox:
    var totalH = 0
    var maxW = 0
    for i, child in w.children:
      let (cw, ch) = child.measure(availableWidth)
      maxW = max(maxW, cw)
      totalH += ch
      if i > 0: totalH += w.gap
    (maxW, totalH)
  of wkHBox:
    var totalW = 0
    var maxH = 0
    for i, child in w.children:
      let (cw, ch) = child.measure(availableWidth)
      if i > 0: totalW += w.gap
      totalW += cw
      maxH = max(maxH, ch)
    (totalW, maxH)
  of wkCenter:
    var totalChildH = 0
    for child in w.centerChildren:
      let (_, ch) = child.measure(w.centerW)
      totalChildH += ch
    (w.centerW, max(w.centerH, totalChildH))
  of wkHeader, wkFooter:
    (availableWidth, 1)
  of wkProgress:
    (availableWidth, 1)
  of wkSeparator:
    (availableWidth, 1)
  of wkSpacer:
    (0, w.spacerHeight)

# =============================================================================
# Rendering (render)
# =============================================================================

## Draw a widget into a buffer.
## buf: target buffer
## x, y: draw origin (top-left of buffer)
## width, height: available size from parent
proc render*(w: Widget, buf: Buffer, x, y, width, height: int, parentStyle: Style = style()) =
  case w.kind
  of wkLabel:
    var effectiveStyle = w.labelStyle
    if w.labelStyle.bg.isDefault and not parentStyle.bg.isDefault:
        effectiveStyle.bg = parentStyle.bg

    buf.drawString(x, y, w.labelText, effectiveStyle)

  of wkBox:
    buf.drawBox(x, y, w.boxW, w.boxH, w.boxStyle, w.boxBorder)

    for cy in 1 ..< (w.boxH - 1):
        for cx in 1 ..< (w.boxW - 1):
            if x + cx < buf.width and y + cy < buf.height:
                buf.setCell(x + cx, y + cy, newCell(" ", w.boxStyle))

    let innerW = max(1, w.boxW - 2)
    var cy = 0
    for child in w.boxChildren:
      let (_, ch) = child.measure(innerW)
      child.render(buf, x + 1, y + 1 + cy, innerW, ch, w.boxStyle)
      cy += ch

  of wkVBox:
    var currentStyle = parentStyle
    if not w.vhboxStyle.bg.isDefault:
        currentStyle.bg = w.vhboxStyle.bg
    if not w.vhboxStyle.fg.isDefault:
        currentStyle.fg = w.vhboxStyle.fg

    if not w.vhboxStyle.bg.isDefault:
        for row in 0 ..< height:
            for col in 0 ..< width:
                if x + col < buf.width and y + row < buf.height:
                    buf.setCell(x + col, y + row, newCell(" ", w.vhboxStyle))

    var totalChildrenH = 0
    for i, child in w.children:
        let(_, ch) = child.measure(width)
        totalChildrenH += ch
        if i > 0: totalChildrenH += w.gap

    let offsetY = max(0, (height - totalChildrenH) div 2)

    # Place children top to bottom
    var cy = y + offsetY
    for child in w.children:
      let (_, ch) = child.measure(width)
      child.render(buf, x, cy, width, ch, currentStyle)
      cy += ch + w.gap

  of wkHBox:
    var currentStyle = parentStyle
    if not w.vhboxStyle.bg.isDefault:
        currentStyle.bg = w.vhboxStyle.bg
    if not w.vhboxStyle.fg.isDefault:
        currentStyle.fg = w.vhboxStyle.fg

    if not w.vhboxStyle.bg.isDefault:
        for row in 0 ..< height:
            for col in 0 ..< width:
                if x + col < buf.width and y + row < buf.height:
                    buf.setCell(x + col, y + row, newCell(" ", w.vhboxStyle))

    var totalChildrenW = 0
    for i, child in w.children:
        let (cw, _) = child.measure(width)
        totalChildrenW += cw
        if i > 0: totalChildrenW += w.gap

    let offsetX = max(0, (width - totalChildrenW) div 2)

    var cx = x + offsetX
    for i, child in w.children:
      if i > 0: cx += w.gap
      let (cw, ch) = child.measure(width)
      child.render(buf, cx, y, cw, height, currentStyle)
      cx += cw

  of wkCenter:
    if not parentStyle.bg.isDefault:
        for cy in 0 ..< height:
            for cx in 0 ..< width:
                if x + cx < buf.width and y + cy < buf.height:
                    buf.setCell(x + cx, y + cy, newCell(" ", parentStyle))

    var totalChildH = 0
    for child in w.centerChildren:
        let (_, ch) = child.measure(w.centerW)
        totalChildH += ch

    let targetH = max(w.centerH, totalChildH)

    let offsetX = max(0, (width - w.centerW) div 2)
    let offsetY = max(0, (height - targetH) div 2)

    var cy = 0
    for child in w.centerChildren:
        let (_, ch) = child.measure(w.centerW)
        child.render(buf, x + offsetX, y + offsetY + cy, w.centerW, ch, parentStyle)
        cy += ch

  of wkHeader:
    # Fill full width with background color
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell(" ", w.barStyle))
    buf.drawString(x + 2, y, w.barText, w.barStyle)

  of wkFooter:
    # Same as header: full-width background + text
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell(" ", w.barStyle))
    buf.drawString(x + 2, y, w.barText, w.barStyle)

  of wkProgress:
    var effectiveStyle = w.progressStyle
    if w.progressStyle.bg.isDefault and not parentStyle.bg.isDefault:
        effectiveStyle.bg = parentStyle.bg

    # Effective bar width: width - 4 (2 chars padding each side)
    let barW = max(0, width - 4)
    let ratio = if w.progressMax > 0: w.progressValue / w.progressMax else: 0.0
    let filled = (ratio * barW.float).int
    # Draw filled (█) and unfilled (░) portions
    for i in 0 ..< barW:
      let ch = if i < filled: "█" else: "░"
      buf.setCell(x + 2 + i, y, newCell(ch, effectiveStyle))

  of wkSeparator:
    var effectiveStyle = w.sepStyle
    if w.sepStyle.bg.isDefault and not parentStyle.bg.isDefault:
        effectiveStyle.bg = parentStyle.bg
    # Draw horizontal line across full width
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell("─", effectiveStyle))

  of wkSpacer:
    discard  # no drawing; just reserves space
