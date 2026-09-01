## =============================================================================
## nimact/core/text.nim
## FreeType2 を使ったテキストレンダリング
##
## フォントのロード、グリフのラスタライズ、キャッシュ、
## ピクセルバッファへのテキスト描画を提供
## =============================================================================

import std/tables
import std/unicode
import ./graphics

# =============================================================================
# FreeType2 C bindings (via raw C emit for reliability)
# =============================================================================

{.passC: "-I/usr/include/freetype2".}
{.passL: "-lfreetype".}

{.emit: """
#include <ft2build.h>
#include FT_FREETYPE_H
typedef struct FT_LibraryRec_* FT_Library_Opaque;
typedef struct FT_FaceRec_* FT_Face_Opaque;
typedef struct FT_GlyphSlotRec_* FT_GlyphSlot_Opaque;
""".}

# Use opaque pointer types matching FreeType's actual types
type
  FtLibrary = pointer
  FtFace = pointer
  FtGlyphSlot = pointer

var
  ftLib: FtLibrary

# =============================================================================
# FreeType functions (all through C emit)
# =============================================================================

proc ftInit(): bool =
  var lib: FtLibrary
  {.emit: """
    FT_Library lib_tmp;
    FT_Error err = FT_Init_FreeType(&lib_tmp);
    `lib` = (void*)lib_tmp;
    `result` = (err == 0);
  """.}
  ftLib = lib

proc ftNewFace(path: cstring, index: clong): FtFace =
  var face: FtFace
  {.emit: """
    FT_Face face_tmp = NULL;
    FT_Error err = FT_New_Face((FT_Library)`ftLib`, `path`, `index`, &face_tmp);
    `face` = (void*)face_tmp;
    `result` = `face`;
  """.}

proc ftSetPixelSizes(face: FtFace, w, h: cuint) =
  {.emit: """
    FT_Set_Pixel_Sizes((FT_Face)`face`, (FT_UInt)`w`, (FT_UInt)`h`);
  """.}

proc ftLoadChar(face: FtFace, charCode: culong): bool =
  {.emit: """
    FT_Error err = FT_Load_Char((FT_Face)`face`, `charCode`, FT_LOAD_RENDER);
    `result` = (err == 0);
  """.}

proc ftGetGlyphSlot(face: FtFace): FtGlyphSlot =
  {.emit: """
    FT_Face f = (FT_Face)`face`;
    `result` = f ? (void*)f->glyph : NULL;
  """.}

proc ftDoneFace(face: FtFace) =
  {.emit: """
    FT_Done_Face((FT_Face)`face`);
  """.}

# Access glyph slot fields via C emit
proc glyphWidth(slot: FtGlyphSlot): int =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (int)(g->metrics.width >> 6) : 0;
  """.}

proc glyphHeight(slot: FtGlyphSlot): int =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (int)(g->metrics.height >> 6) : 0;
  """.}

proc glyphBearingX(slot: FtGlyphSlot): int =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (int)(g->metrics.horiBearingX >> 6) : 0;
  """.}

proc glyphBearingY(slot: FtGlyphSlot): int =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (int)(g->metrics.horiBearingY >> 6) : 0;
  """.}

proc glyphAdvance(slot: FtGlyphSlot): int =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (int)(g->advance.x >> 6) : 0;
  """.}

proc glyphBitmapRows(slot: FtGlyphSlot): int =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (int)g->bitmap.rows : 0;
  """.}

proc glyphBitmapWidth(slot: FtGlyphSlot): int =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (int)g->bitmap.width : 0;
  """.}

proc glyphBitmapPitch(slot: FtGlyphSlot): int =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (int)g->bitmap.pitch : 0;
  """.}

proc glyphBitmapBuffer(slot: FtGlyphSlot): ptr uint8 =
  {.emit: """
    FT_GlyphSlot g = (FT_GlyphSlot)`slot`;
    `result` = g ? (uint8_t*)g->bitmap.buffer : NULL;
  """.}

# =============================================================================
# Font search paths
# =============================================================================

const defaultFontPaths = [
  "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf",
  "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
  "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
  "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
  "/usr/share/fonts/TTF/DejaVuSans.ttf",
  "/usr/share/fonts/liberation-sans/LiberationSans-Regular.ttf",
  "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
  "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
]

const defaultBoldFontPaths = [
  "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
  "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
  "/usr/share/fonts/truetype/ubuntu/Ubuntu-B.ttf",
  "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
  "/usr/share/fonts/liberation-sans/LiberationSans-Bold.ttf",
]

# =============================================================================
# Glyph cache
# =============================================================================

type
  CachedGlyph* = ref object
    bitmap*: seq[uint8]
    width*, height*: int
    bearingX*, bearingY*: int
    advance*: int

  GlyphKey = object
    codepoint: uint32
    size: int

  GlyphCache* = ref object
    cache*: Table[GlyphKey, CachedGlyph]

proc newGlyphCache*(): GlyphCache =
  GlyphCache(cache: initTable[GlyphKey, CachedGlyph]())

proc getGlyph(cache: GlyphCache, codepoint: uint32, size: int): CachedGlyph =
  let key = GlyphKey(codepoint: codepoint, size: size)
  if key in cache.cache:
    return cache.cache[key]
  nil

proc putGlyph(cache: GlyphCache, codepoint: uint32, size: int, glyph: CachedGlyph) =
  let key = GlyphKey(codepoint: codepoint, size: size)
  cache.cache[key] = glyph

# =============================================================================
# Font type
# =============================================================================

type
  Font* = ref object
    face*: FtFace
    glyphCache*: GlyphCache
    size*: int
    name*: string
    isBold*: bool

var ftInitialized = false

proc initFreeTypeLib() =
  if ftInitialized: return
  if not ftInit():
    raise newException(IOError, "Failed to initialize FreeType")
  ftInitialized = true

proc findFont(bold: bool = false): string =
  if bold:
    for path in defaultBoldFontPaths:
      try:
        let f = open(path)
        if f != nil:
          close(f)
          return path
      except CatchableError:
        discard
  else:
    for path in defaultFontPaths:
      try:
        let f = open(path)
        if f != nil:
          close(f)
          return path
      except CatchableError:
        discard
  ""

proc loadFont*(path: string, size: int = 16, bold: bool = false): Font =
  initFreeTypeLib()

  var resolvedPath = path
  if path.len == 0:
    resolvedPath = findFont(bold)
    if resolvedPath.len == 0:
      raise newException(IOError, "No font found on system")

  let face = ftNewFace(resolvedPath.cstring, 0)
  if face == nil:
    raise newException(IOError, "Failed to load font: " & resolvedPath)

  ftSetPixelSizes(face, 0, size.cuint)

  Font(
    face: face,
    glyphCache: newGlyphCache(),
    size: size,
    name: resolvedPath,
    isBold: bold
  )

proc closeFont*(font: Font) =
  if font.face != nil:
    ftDoneFace(font.face)
    font.face = nil

# =============================================================================
# Glyph loading
# =============================================================================

proc loadGlyph(font: Font, codepoint: uint32): CachedGlyph =
  let cached = font.glyphCache.getGlyph(codepoint, font.size)
  if cached != nil:
    return cached

  if not ftLoadChar(font.face, culong(codepoint)):
    return nil

  let slot = ftGetGlyphSlot(font.face)
  if slot == nil:
    return nil

  let bmW = glyphBitmapWidth(slot)
  let bmH = glyphBitmapRows(slot)
  let bmPitch = glyphBitmapPitch(slot)
  let bmBuf = glyphBitmapBuffer(slot)

  let glyph = CachedGlyph(
    width: bmW,
    height: bmH,
    bearingX: glyphBearingX(slot),
    bearingY: glyphBearingY(slot),
    advance: glyphAdvance(slot),
    bitmap: newSeq[uint8](bmW * max(1, bmH))
  )

  # Copy bitmap data
  if bmBuf != nil and bmW > 0 and bmH > 0:
    let rawPtr = cast[ptr UncheckedArray[uint8]](bmBuf)
    for y in 0 ..< bmH:
      for x in 0 ..< bmW:
        let srcIdx = y * abs(bmPitch) + x
        if srcIdx < bmH * abs(bmPitch):
          glyph.bitmap[y * bmW + x] = rawPtr[srcIdx]

  font.glyphCache.putGlyph(codepoint, font.size, glyph)
  glyph

# =============================================================================
# Text measurement
# =============================================================================

proc measureText*(font: Font, text: string): (int, int) =
  var totalWidth = 0
  var maxHeight = 0

  for rune in text.runes:
    if rune == Rune(0x0A):
      maxHeight += font.size
      continue
    let glyph = font.loadGlyph(rune.uint32)
    if glyph != nil:
      totalWidth += glyph.advance
      let h = glyph.bearingY + (font.size - glyph.bearingY)
      if h > maxHeight:
        maxHeight = h

  if maxHeight == 0:
    maxHeight = font.size
  (totalWidth, maxHeight)

proc measureTextWidth*(font: Font, text: string): int =
  font.measureText(text)[0]

proc lineHeight*(font: Font): int =
  font.size + font.size div 4

# =============================================================================
# Text rendering to PixelBuffer / GraphicsContext
# =============================================================================

proc drawText*(buf: PixelBuffer, x, y: int, text: string,
               font: Font, color: Color) =
  var cursorX = x
  var cursorY = y

  for rune in text.runes:
    if rune == Rune(0x0A):
      cursorX = x
      cursorY += font.lineHeight()
      continue

    let glyph = font.loadGlyph(rune.uint32)
    if glyph == nil:
      cursorX += font.size div 2
      continue

    let startX = cursorX + glyph.bearingX
    let startY = cursorY + font.size - glyph.bearingY

    for gy in 0 ..< glyph.height:
      for gx in 0 ..< glyph.width:
        let alpha = glyph.bitmap[gy * glyph.width + gx]
        if alpha == 0: continue

        let px = startX + gx
        let py = startY + gy
        if px < 0 or px >= buf.width or py < 0 or py >= buf.height:
          continue

        let a = alpha.int
        let sa = color.a.int
        let finalA = (a * sa) div 255

        if finalA == 0: continue
        if finalA == 255:
          buf.pixels[py * buf.width + px] = color.toUInt32()
        else:
          let dst = buf.pixels[py * buf.width + px]
          let da = ((dst shr 24) and 0xFF).int
          let outA = min(255, finalA + da - (finalA * da) div 255)
          if outA == 0: continue
          let outR = uint8((color.r.int * finalA + ((dst shr 16) and 0xFF).int * da * (255 - finalA) div 255) div outA)
          let outG = uint8((color.g.int * finalA + ((dst shr 8) and 0xFF).int * da * (255 - finalA) div 255) div outA)
          let outB = uint8((color.b.int * finalA + (dst and 0xFF).int * da * (255 - finalA) div 255) div outA)
          buf.pixels[py * buf.width + px] = uint32(outB) or
            (uint32(outG) shl 8) or (uint32(outR) shl 16) or (uint32(outA) shl 24)

proc drawText*(gc: GraphicsContext, x, y: int, text: string,
               font: Font, color: Color) =
  let (gx, gy) = gc.localToGlobal(x, y)
  gc.buffer.drawText(gx, gy, text, font, color)

proc drawTextCentered*(buf: PixelBuffer, centerX, y: int, text: string,
                       font: Font, color: Color) =
  let (tw, _) = font.measureText(text)
  buf.drawText(centerX - tw div 2, y, text, font, color)

proc drawTextCentered*(gc: GraphicsContext, centerX, y: int, text: string,
                       font: Font, color: Color) =
  let (gx, gy) = gc.localToGlobal(centerX, y)
  gc.buffer.drawTextCentered(gx, gy, text, font, color)

proc drawTextWrapped*(buf: PixelBuffer, x, y, maxWidth: int, text: string,
                      font: Font, color: Color): int =
  var cursorX = x
  var cursorY = y
  var lineStart = 0
  let lh = font.lineHeight()
  let runes = toRunes(text)

  var i = 0
  while i < runes.len:
    if runes[i] == Rune(0x0A):
      let line = $runes[lineStart ..< i]
      buf.drawText(cursorX, cursorY, line, font, color)
      cursorY += lh
      cursorX = x
      lineStart = i + 1
      i += 1
      continue

    let partial = $runes[lineStart .. i]
    let (pw, _) = font.measureText(partial)
    if pw > maxWidth and i > lineStart:
      let line = $runes[lineStart ..< i]
      buf.drawText(cursorX, cursorY, line, font, color)
      cursorY += lh
      cursorX = x
      lineStart = i
    else:
      i += 1

  if lineStart < runes.len:
    let line = $runes[lineStart .. ^1]
    buf.drawText(cursorX, cursorY, line, font, color)
    cursorY += lh

  cursorY - y
