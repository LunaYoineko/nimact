## =============================================================================
## nimact/core/graphics.nim
## ピクセルバッファと2D描画プリミティブ
##
## GUI レンダリングの基盤となるピクセル単位の描画を提供:
##   - Color: 32-bit ARGB カラー
##   - PixelBuffer: ピクセル配列
##   - drawRect, fillRect, drawRoundedRect: 四角形描画
##   - drawLine: 線描画
##   - drawCircle, fillCircle: 円描画
##   - blendColor: アルファブレンド
## =============================================================================

# =============================================================================
# Color type (32-bit ARGB)
# =============================================================================

type
  Color* = object
    r*, g*, b*, a*: uint8

proc rgb*(r, g, b: uint8): Color {.inline.} =
  Color(r: r, g: g, b: b, a: 255)

proc rgba*(r, g, b, a: uint8): Color {.inline.} =
  Color(r: r, g: g, b: b, a: a)

proc hex*(color: uint32): Color {.inline.} =
  Color(
    r: uint8((color shr 16) and 0xFF),
    g: uint8((color shr 8) and 0xFF),
    b: uint8(color and 0xFF),
    a: 255
  )

proc toUInt32*(c: Color): uint32 {.inline.} =
  ## Convert to BGRA format (native for most Wayland compositors)
  uint32(c.b) or (uint32(c.g) shl 8) or (uint32(c.r) shl 16) or (uint32(c.a) shl 24)

# =============================================================================
# Built-in color palette
# =============================================================================

const
  colBgDark*    = Color(r: 30,  g: 34,  b: 42,  a: 255)
  colBgCard*    = Color(r: 40,  g: 44,  b: 52,  a: 255)
  colBgFocus*   = Color(r: 50,  g: 56,  b: 66,  a: 255)
  colBgHover*   = Color(r: 55,  g: 62,  b: 72,  a: 255)
  colBgPressed* = Color(r: 45,  g: 50,  b: 60,  a: 255)

  colBlue*      = Color(r: 97,  g: 175, b: 239, a: 255)
  colPurple*    = Color(r: 198, g: 120, b: 221, a: 255)
  colGreen*     = Color(r: 152, g: 195, b: 121, a: 255)
  colYellow*    = Color(r: 229, g: 192, b: 123, a: 255)
  colRed*       = Color(r: 224, g: 108, b: 117, a: 255)
  colCyan*      = Color(r: 86,  g: 182, b: 194, a: 255)

  colText*      = Color(r: 220, g: 223, b: 228, a: 255)
  colTextMuted* = Color(r: 92,  g: 99,  b: 112, a: 255)
  colWhite*     = Color(r: 255, g: 255, b: 255, a: 255)
  colBlack*     = Color(r: 0,   g: 0,   b: 0,   a: 255)
  colTransparent* = Color(r: 0, g: 0,   b: 0,   a: 0)

# =============================================================================
# Pixel Buffer
# =============================================================================

type
  PixelBuffer* = ref object
    width*, height*: int
    pixels*: seq[uint32]  # BGRA format

proc newPixelBuffer*(width, height: int): PixelBuffer =
  PixelBuffer(
    width: width,
    height: height,
    pixels: newSeq[uint32](width * height)
  )

proc clear*(buf: PixelBuffer, color: Color) =
  let c = color.toUInt32
  for i in 0 ..< buf.pixels.len:
    buf.pixels[i] = c

proc setPixel*(buf: PixelBuffer, x, y: int, color: Color) {.inline.} =
  if x >= 0 and x < buf.width and y >= 0 and y < buf.height:
    buf.pixels[y * buf.width + x] = color.toUInt32

proc getPixel*(buf: PixelBuffer, x, y: int): Color {.inline.} =
  if x >= 0 and x < buf.width and y >= 0 and y < buf.height:
    let c = buf.pixels[y * buf.width + x]
    Color(
      r: uint8((c shr 16) and 0xFF),
      g: uint8((c shr 8) and 0xFF),
      b: uint8(c and 0xFF),
      a: uint8((c shr 24) and 0xFF)
    )
  else:
    colTransparent

proc setPixelBlend*(buf: PixelBuffer, x, y: int, color: Color) =
  ## Set pixel with alpha blending
  if x < 0 or x >= buf.width or y < 0 or y >= buf.height:
    return
  if color.a == 0:
    return
  if color.a == 255:
    buf.pixels[y * buf.width + x] = color.toUInt32
    return

  let dst = buf.pixels[y * buf.width + x]
  let da = uint8((dst shr 24) and 0xFF)
  let sa = color.a.int
  let daI = da.int
  let outA = min(255, sa + daI - (sa * daI) div 255)
  if outA == 0:
    return
  let outR = uint8(((color.r.int * sa + dst.int and 0xFF0000 shr 16).int * sa +
    ((dst shr 16) and 0xFF).int * daI * (255 - sa) div 255) div outA)
  let outG = uint8(((color.g.int * sa + ((dst shr 8) and 0xFF).int * daI * (255 - sa) div 255)) div outA)
  let outB = uint8(((color.b.int * sa + (dst and 0xFF).int * daI * (255 - sa) div 255)) div outA)

  buf.pixels[y * buf.width + x] = uint32(outB) or
    (uint32(outG) shl 8) or (uint32(outR) shl 16) or (uint32(outA) shl 24)

# =============================================================================
# Rectangle drawing
# =============================================================================

proc fillRect*(buf: PixelBuffer, x, y, w, h: int, color: Color) =
  let c = color.toUInt32
  for row in y ..< y + h:
    if row < 0 or row >= buf.height: continue
    for col in x ..< x + w:
      if col < 0 or col >= buf.width: continue
      buf.pixels[row * buf.width + col] = c

proc drawRect*(buf: PixelBuffer, x, y, w, h: int, color: Color, thickness: int = 1) =
  for t in 0 ..< thickness:
    # Top
    for cx in x + t ..< x + w - t:
      buf.setPixel(cx, y + t, color)
    # Bottom
    for cx in x + t ..< x + w - t:
      buf.setPixel(cx, y + h - 1 - t, color)
    # Left
    for cy in y + t ..< y + h - t:
      buf.setPixel(x + t, cy, color)
    # Right
    for cy in y + t ..< y + h - t:
      buf.setPixel(x + w - 1 - t, cy, color)

proc fillRoundedRect*(buf: PixelBuffer, x, y, w, h, radius: int, color: Color) =
  let c = color.toUInt32
  for row in y ..< y + h:
    if row < 0 or row >= buf.height: continue
    for col in x ..< x + w:
      if col < 0 or col >= buf.width: continue

      var inside = true
      # Check corners
      if row < y + radius and col < x + radius:
        let dx = (x + radius - col)
        let dy = (y + radius - row)
        if dx * dx + dy * dy > radius * radius:
          inside = false
      elif row < y + radius and col >= x + w - radius:
        let dx = (col - (x + w - radius - 1))
        let dy = (y + radius - row)
        if dx * dx + dy * dy > radius * radius:
          inside = false
      elif row >= y + h - radius and col < x + radius:
        let dx = (x + radius - col)
        let dy = (row - (y + h - radius - 1))
        if dx * dx + dy * dy > radius * radius:
          inside = false
      elif row >= y + h - radius and col >= x + w - radius:
        let dx = (col - (x + w - radius - 1))
        let dy = (row - (y + h - radius - 1))
        if dx * dx + dy * dy > radius * radius:
          inside = false

      if inside:
        buf.pixels[row * buf.width + col] = c

proc drawRoundedRect*(buf: PixelBuffer, x, y, w, h, radius: int,
                       color: Color, thickness: int = 1) =
  for t in 0 ..< thickness:
    for row in y + t ..< y + h - t:
      if row < 0 or row >= buf.height: continue
      for col in x + t ..< x + w - t:
        if col < 0 or col >= buf.width: continue

        var draw = false
        # Top edge
        if row == y + t and col >= x + t + radius and col < x + w - t - radius:
          draw = true
        # Bottom edge
        elif row == y + h - 1 - t and col >= x + t + radius and col < x + w - t - radius:
          draw = true
        # Left edge
        elif col == x + t and row >= y + t + radius and row < y + h - t - radius:
          draw = true
        # Right edge
        elif col == x + w - 1 - t and row >= y + t + radius and row < y + h - t - radius:
          draw = true
        # Corners (on the border of the rounded rect)
        elif row < y + t + radius and col < x + t + radius:
          let dx = (x + t + radius - col)
          let dy = (y + t + radius - row)
          let dist2 = dx * dx + dy * dy
          let ri = radius - t
          let ro = radius
          if dist2 <= ro * ro and dist2 > (ri - 1) * (ri - 1):
            draw = true
        elif row < y + t + radius and col >= x + w - t - radius:
          let dx = (col - (x + w - t - radius - 1))
          let dy = (y + t + radius - row)
          let dist2 = dx * dx + dy * dy
          let ri = radius - t
          let ro = radius
          if dist2 <= ro * ro and dist2 > (ri - 1) * (ri - 1):
            draw = true
        elif row >= y + h - t - radius and col < x + t + radius:
          let dx = (x + t + radius - col)
          let dy = (row - (y + h - t - radius - 1))
          let dist2 = dx * dx + dy * dy
          let ri = radius - t
          let ro = radius
          if dist2 <= ro * ro and dist2 > (ri - 1) * (ri - 1):
            draw = true
        elif row >= y + h - t - radius and col >= x + w - t - radius:
          let dx = (col - (x + w - t - radius - 1))
          let dy = (row - (y + h - t - radius - 1))
          let dist2 = dx * dx + dy * dy
          let ri = radius - t
          let ro = radius
          if dist2 <= ro * ro and dist2 > (ri - 1) * (ri - 1):
            draw = true

        if draw:
          buf.pixels[row * buf.width + col] = color.toUInt32

# =============================================================================
# Circle drawing
# =============================================================================

proc fillCircle*(buf: PixelBuffer, cx, cy, radius: int, color: Color) =
  let c = color.toUInt32
  for y in (cy - radius) .. (cy + radius):
    if y < 0 or y >= buf.height: continue
    for x in (cx - radius) .. (cx + radius):
      if x < 0 or x >= buf.width: continue
      let dx = x - cx
      let dy = y - cy
      if dx * dx + dy * dy <= radius * radius:
        buf.pixels[y * buf.width + x] = c

proc drawCircle*(buf: PixelBuffer, cx, cy, radius: int, color: Color, thickness: int = 1) =
  for y in (cy - radius - 1) .. (cy + radius + 1):
    if y < 0 or y >= buf.height: continue
    for x in (cx - radius - 1) .. (cx + radius + 1):
      if x < 0 or x >= buf.width: continue
      let dx = x - cx
      let dy = y - cy
      let dist2 = dx * dx + dy * dy
      let ri = radius - thickness
      let ro = radius
      if dist2 <= ro * ro and dist2 >= ri * ri:
        buf.pixels[y * buf.width + x] = color.toUInt32

# =============================================================================
# Line drawing (Bresenham)
# =============================================================================

proc drawLine*(buf: PixelBuffer, x0, y0, x1, y1: int, color: Color, thickness: int = 1) =
  var
    x = x0
    y = y0
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = if x0 < x1: 1 else: -1
    sy = if y0 < y1: 1 else: -1
    err = dx - dy

  while true:
    for t in 0 ..< thickness:
      buf.setPixel(x, y + t, color)
      buf.setPixel(x + t, y, color)

    if x == x1 and y == y1: break
    let e2 = 2 * err
    if e2 > -dy:
      err -= dy
      x += sx
    if e2 < dx:
      err += dx
      y += sy

# =============================================================================
# Gradient fills
# =============================================================================

proc lerpColor*(a, b: Color, t: float): Color =
  let t8 = uint8(t * 255.0)
  let mt = 255 - t8.int
  Color(
    r: uint8((a.r.int * mt + b.r.int * t8.int) div 255),
    g: uint8((a.g.int * mt + b.g.int * t8.int) div 255),
    b: uint8((a.b.int * mt + b.b.int * t8.int) div 255),
    a: uint8((a.a.int * mt + b.a.int * t8.int) div 255)
  )

proc fillGradientV*(buf: PixelBuffer, x, y, w, h: int,
                     topColor, bottomColor: Color) =
  for row in 0 ..< h:
    let t = row.float / max(1, h - 1).float
    let c = lerpColor(topColor, bottomColor, t)
    for col in x ..< x + w:
      buf.setPixel(col, y + row, c)

proc fillGradientH*(buf: PixelBuffer, x, y, w, h: int,
                     leftColor, rightColor: Color) =
  for col in 0 ..< w:
    let t = col.float / max(1, w - 1).float
    let c = lerpColor(leftColor, rightColor, t)
    for row in y ..< y + h:
      buf.setPixel(x + col, row, c)

# =============================================================================
# Clipping support
# =============================================================================

type
  Rect* = object
    x*, y*, w*, h*: int

  ClipRect* = object
    enabled*: bool
    rect*: Rect

proc newClipRect*(x, y, w, h: int): ClipRect =
  ClipRect(enabled: true, rect: Rect(x: x, y: y, w: w, h: h))

proc noClip*(): ClipRect =
  ClipRect(enabled: false)

proc contains*(cr: ClipRect, x, y: int): bool =
  if not cr.enabled: return true
  x >= cr.rect.x and x < cr.rect.x + cr.rect.w and
  y >= cr.rect.y and y < cr.rect.y + cr.rect.h

proc intersects*(cr: ClipRect, x, y, w, h: int): bool =
  if not cr.enabled: return true
  let ax1 = cr.rect.x
  let ay1 = cr.rect.y
  let ax2 = cr.rect.x + cr.rect.w
  let ay2 = cr.rect.y + cr.rect.h
  let bx1 = x
  let by1 = y
  let bx2 = x + w
  let by2 = y + h
  ax1 < bx2 and ax2 > bx1 and ay1 < by2 and ay2 > by1

# =============================================================================
# Graphics context (for rendering pipeline)
# =============================================================================

type
  GraphicsContext* = ref object
    buffer*: PixelBuffer
    offsetX*, offsetY*: int
    clip*: ClipRect

proc newGraphicsContext*(buf: PixelBuffer): GraphicsContext =
  GraphicsContext(
    buffer: buf,
    offsetX: 0,
    offsetY: 0,
    clip: noClip()
  )

proc localToGlobal*(gc: GraphicsContext, x, y: int): (int, int) =
  (x + gc.offsetX, y + gc.offsetY)

proc drawRect*(gc: GraphicsContext, x, y, w, h: int, color: Color) =
  let (gx, gy) = gc.localToGlobal(x, y)
  gc.buffer.fillRect(gx, gy, w, h, color)

proc fillRect*(gc: GraphicsContext, x, y, w, h: int, color: Color) =
  let (gx, gy) = gc.localToGlobal(x, y)
  gc.buffer.fillRect(gx, gy, w, h, color)

proc fillRoundedRect*(gc: GraphicsContext, x, y, w, h, radius: int, color: Color) =
  let (gx, gy) = gc.localToGlobal(x, y)
  gc.buffer.fillRoundedRect(gx, gy, w, h, radius, color)

proc drawRoundedRect*(gc: GraphicsContext, x, y, w, h, radius: int,
                       color: Color, thickness: int = 1) =
  let (gx, gy) = gc.localToGlobal(x, y)
  gc.buffer.drawRoundedRect(gx, gy, w, h, radius, color, thickness)

proc drawLine*(gc: GraphicsContext, x0, y0, x1, y1: int,
               color: Color, thickness: int = 1) =
  let (gx0, gy0) = gc.localToGlobal(x0, y0)
  let (gx1, gy1) = gc.localToGlobal(x1, y1)
  gc.buffer.drawLine(gx0, gy0, gx1, gy1, color, thickness)

proc fillCircle*(gc: GraphicsContext, cx, cy, radius: int, color: Color) =
  let (gcx, gcy) = gc.localToGlobal(cx, cy)
  gc.buffer.fillCircle(gcx, gcy, radius, color)

proc drawCircle*(gc: GraphicsContext, cx, cy, radius: int,
                 color: Color, thickness: int = 1) =
  let (gcx, gcy) = gc.localToGlobal(cx, cy)
  gc.buffer.drawCircle(gcx, gcy, radius, color, thickness)

proc fillGradientV*(gc: GraphicsContext, x, y, w, h: int,
                     topColor, bottomColor: Color) =
  let (gx, gy) = gc.localToGlobal(x, y)
  gc.buffer.fillGradientV(gx, gy, w, h, topColor, bottomColor)
