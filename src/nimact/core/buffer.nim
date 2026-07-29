## =============================================================================
## nimact/core/buffer.nim
## TUI framework buffer and drawing primitives
##
## This module provides:
##   - Color: TrueColor (24-bit) color representation
##   - Style: text decoration (fg, bg, bold, dim, etc.)
##   - Cell: single character drawing info (char + style)
##   - Buffer: 2D cell array representing the screen
##   - drawString / drawBox: low-level drawing functions
##
## Usage:
##   let buf = newBuffer(80, 24)
##   buf.drawString(0, 0, "Hello", style(fg = colGreen))
##   buf.drawBox(5, 3, 20, 10, style(fg = colBlue))
## =============================================================================

# =============================================================================
# Color type: TrueColor (24-bit RGB)
# =============================================================================
type
    Color* = object
        r*, g*, b*: uint8       ## RGB channels (0-255)
        isDefault*: bool        ## true to use terminal default color

## Create a Color from RGB values
proc rgb*(r, g, b: uint8): Color =
    Color(r: r, g: g, b: b, isDefault: false)

## Return terminal default color
proc defaultColor*(): Color =
    Color(isDefault: true)

# =============================================================================
# Built-in color palette (Nord / OneDark / Dracula based)
# =============================================================================
const
  # --- Dark backgrounds ---
  colBgDark*     = Color(r: 30,  g: 34,  b: 42,  isDefault: false) ## Main background (#1e222a)
  colBgCard*     = Color(r: 40,  g: 44,  b: 52,  isDefault: false) ## Card/panel background (#282c34)
  colBgFocus*    = Color(r: 50,  g: 56,  b: 66,  isDefault: false) ## Focused background (#323842)

  # --- Accent colors ---
  colBlue*       = Color(r: 97,  g: 175, b: 239, isDefault: false) ## Blue (#61afef)
  colPurple*     = Color(r: 198, g: 120, b: 221, isDefault: false) ## Purple (#c678dd)
  colGreen*      = Color(r: 152, g: 195, b: 121, isDefault: false) ## Green (#98c379)
  colYellow*     = Color(r: 229, g: 192, b: 123, isDefault: false) ## Yellow (#e5c07b)
  colRed*        = Color(r: 224, g: 108, b: 117, isDefault: false) ## Red (#e06c75)
  colCyan*       = Color(r: 86,  g: 182, b: 194, isDefault: false) ## Cyan (#56b6c2)

  # --- Text colors ---
  colText*       = Color(r: 220, g: 223, b: 228, isDefault: false) ## Main text (#dcdfe4)
  colTextMuted*  = Color(r: 92,  g: 99,  b: 112, isDefault: false) ## Muted text (#5c6370)
  colWhite*      = Color(r: 255, g: 255, b: 255, isDefault: false) ## Pure white

# =============================================================================
# Style type: text decoration
# =============================================================================
type
    Style* = object
        fg*: Color    ## Foreground color
        bg*: Color    ## Background color
        bold*: bool   ## Bold (ANSI SGR: \e[1m)
        dim*: bool    ## Dim (ANSI SGR: \e[2m)
        italic*: bool ## Italic (ANSI: \e[3m)
        underline*: bool ## Underline (ANSI: \e[4m)
        reverse*: bool ## Reverse (ANSI: \e[7m)

## Create a Style. All parameters optional, defaults to no decoration.
proc style*(fg: Color = defaultColor(), bg: Color = defaultColor(),
            bold: bool = false, dim: bool = false, italic: bool = false, underline: bool = false, reverse: bool = false): Style =
    Style(fg: fg, bg: bg, bold: bold, dim: dim, italic: italic, underline: underline, reverse: reverse)

# =============================================================================
# Cell type: single buffer cell
# =============================================================================
type
    Cell* = object
        ch*: string     ## Display character (string for Unicode)
        style*: Style   ## Cell style

    ## Buffer value object (defined as value type, not ref)
    BufferObj* = object
        width*, height*: int   ## Buffer width and height in characters
        cells*: seq[Cell]      ## Cell array (row-major: cells[y * width + x])

    ## Buffer reference type (heap-allocated)
    Buffer* = ref BufferObj

## Create a new Cell
proc newCell*(ch: string = " ", style: Style = style()): Cell =
    Cell(ch: ch, style: style)

## Create a new buffer with width x height cells, initialized to spaces.
## Returns nil if width or height is <= 0.
proc newBuffer*(width, height: int): Buffer =
    if width <= 0 or height <= 0:
        return nil
    let size = width * height
    var cells = newSeq[Cell](size)
    for i in 0 ..< size:
        cells[i] = newCell()
    Buffer(width: width, height: height, cells: cells)

## Set a cell at (x, y). Out-of-bounds coordinates are ignored.
proc setCell*(buf: Buffer, x, y: int, cell: Cell) =
    if x >= 0 and x < buf.width and y >= 0 and y < buf.height:
        buf.cells[y * buf.width + x] = cell

        
## Get cell at (x, y). Returns empty cell if out of bounds.
proc getCell*(buf: Buffer, x, y: int): Cell =
    if x >= 0 and x < buf.width and y >= 0 and y < buf.height:
        return buf.cells[y * buf.width + x]
    else:
        return newCell()
# =============================================================================
# Low-level drawing functions
# =============================================================================

## Draw a string into the buffer.
## Characters exceeding the right edge are truncated.
import unicode

## Character width detection (0=zero-width, 1=narrow, 2=wide)
proc runeWidth*(r: Rune): int =
    let cp = r.int
    # Zero-width characters
    if (cp >= 0x0300 and cp <= 0x036F) or  # Combining Diacritical Marks
       (cp >= 0x0483 and cp <= 0x0489) or  # Combining Cyrillic Marks
       (cp >= 0x0610 and cp <= 0x061A) or  # Combining Arabic Marks
       (cp >= 0x06D6 and cp <= 0x06DC) or  # Combining Arabic Marks
       (cp >= 0x0E31 and cp <= 0x0E3A) or  # Thai Combining Marks
       (cp >= 0x1AB0 and cp <= 0x1ACE) or  # Combining Marks Extended
       (cp >= 0x1DC0 and cp <= 0x1DFF) or  # Combining Marks Supplement
       (cp >= 0x200B and cp <= 0x200F) or  # ZWSP, LRM, RLM, ZWNJ, ZWJ
       (cp >= 0x2028 and cp <= 0x2029) or  # Line/Paragraph Separator
       (cp >= 0x2060 and cp <= 0x206F) or  # Word Joiner, Invisible Operators
       (cp >= 0xFE00 and cp <= 0xFE0F) or  # Variation Selectors
       (cp >= 0xFE20 and cp <= 0xFE2F) or  # Combining Half Marks
       (cp == 0x200D):                      # ZWJ
        return 0
    # Wide characters (CJK, fullwidth, emoji)
    if (cp >= 0x1100 and cp <= 0x115F) or  # Hangul Jamo
        (cp >= 0x3040 and cp <= 0x309F) or # ひらがな
        (cp >= 0x30A0 and cp <= 0x30FF) or # カタカナ
        (cp >= 0x2E80 and cp <= 0xA4CF) or # CJK Radicals, Kanji, etc.
        (cp >= 0xAC00 and cp <= 0xD7A3) or # Hangul Syllables
        (cp >= 0xF900 and cp <= 0xFAFF) or # CJK Compatibility
        (cp >= 0xFE10 and cp <= 0xFE19) or # Vertical Forms
        (cp >= 0xFF01 and cp <= 0xFF60) or # Fullwidth Forms
        (cp >= 0xFFE0 and cp <= 0xFFE6) or
        (cp >= 0x1F300 and cp <= 0x1F64F) or # Emoticons
        (cp >= 0x1F900 and cp <= 0x1F9FF) or # Supplemental Emoji
        (cp >= 0x1F3FB and cp <= 0x1F3FF) or # Emoji Skin Tone Modifiers
        (cp >= 0x1F1E0 and cp <= 0x1F1FF) or # Regional Indicators (flags)
        (cp >= 0x1FA00 and cp <= 0x1FA6F) or # Chess Symbols
        (cp >= 0x1FA70 and cp <= 0x1FAFF) or # Symbols Extended-A
        # Ambiguous width (East Asian locale: 2 columns)
        (cp >= 0x00A1 and cp <= 0x00A1) or # ¡
        (cp >= 0x00A4 and cp <= 0x00A4) or # ¤
        (cp >= 0x00A7 and cp <= 0x00A8) or # § ¨
        (cp >= 0x00AA and cp <= 0x00AA) or # ª
        (cp >= 0x00AD and cp <= 0x00AD) or # Soft Hyphen
        (cp >= 0x00AF and cp <= 0x00AF) or # ¯
        (cp >= 0x00B0 and cp <= 0x00B1) or # ° ±
        (cp >= 0x00B4 and cp <= 0x00B4) or # ´
        (cp >= 0x00B6 and cp <= 0x00B8) or # ¶ · ¸
        (cp >= 0x00BA and cp <= 0x00BA) or # º
        (cp >= 0x00C6 and cp <= 0x00C6) or # Æ
        (cp >= 0x00D0 and cp <= 0x00D0) or # Ð
        (cp >= 0x00D7 and cp <= 0x00D8) or # × Ò
        (cp >= 0x00DE and cp <= 0x00E1) or # Þ ß À Á
        (cp >= 0x00E6 and cp <= 0x00E6) or # æ
        (cp >= 0x00E8 and cp <= 0x00EA) or # è é ê
        (cp >= 0x00EC and cp <= 0x00ED) or # ì í
        (cp >= 0x00F0 and cp <= 0x00F0) or # ð
        (cp >= 0x00F2 and cp <= 0x00F3) or # ò ó
        (cp >= 0x00F7 and cp <= 0x00F8) or # ÷ ø
        (cp >= 0x00FA and cp <= 0x00FA) or # ú
        (cp >= 0x00FC and cp <= 0x00FC) or # ü
        (cp >= 0x0101 and cp <= 0x0101) or # ā
        (cp >= 0x0111 and cp <= 0x0111) or # đ
        (cp >= 0x0113 and cp <= 0x0113) or # ē
        (cp >= 0x011B and cp <= 0x011B) or # ě
        (cp >= 0x0127 and cp <= 0x0127) or # ħ
        (cp >= 0x012B and cp <= 0x012B) or # ī
        (cp >= 0x0131 and cp <= 0x0131) or # ı
        (cp >= 0x0138 and cp <= 0x0138) or # k
        (cp >= 0x0141 and cp <= 0x0148) or # Ł ł Ń ń Ņ ņ Ň ň
        (cp >= 0x014D and cp <= 0x014D) or # ō
        (cp >= 0x0152 and cp <= 0x0153) or # Œ œ
        (cp >= 0x0166 and cp <= 0x0167) or # Ŧ ŧ
        (cp >= 0x016B and cp <= 0x016B) or # ū
        (cp >= 0x016D and cp <= 0x016D) or # ŭ
        (cp >= 0x017F and cp <= 0x017F) or # ſ
        (cp >= 0x0192 and cp <= 0x0192) or # ƒ
        (cp >= 0x01A1 and cp <= 0x01A1) or # Ơ
        (cp >= 0x01B0 and cp <= 0x01B0) or # ư
        (cp >= 0x01C4 and cp <= 0x01CC) or # Ǆ-ǌ
        (cp >= 0x01DD and cp <= 0x01DD) or # ǝ
        (cp >= 0x0251 and cp <= 0x0251) or # ɑ
        (cp >= 0x0261 and cp <= 0x0261) or # ɡ
        (cp >= 0x02C4 and cp <= 0x02C4) or # ˓
        (cp >= 0x02C7 and cp <= 0x02C7) or # ˇ
        (cp >= 0x02C9 and cp <= 0x02CB) or # ˉ ˘ ˙
        (cp >= 0x02CD and cp <= 0x02CD) or # ˍ
        (cp >= 0x02D9 and cp <= 0x02D9) or # ˙
        (cp >= 0x0384 and cp <= 0x0385) or # ΅ Ά
        (cp >= 0x038C and cp <= 0x038C) or # Ό
        (cp >= 0x03A2 and cp <= 0x03A2) or # Ϣ (not assigned)
        (cp >= 0x0401 and cp <= 0x0401) or # Ё
        (cp >= 0x040F and cp <= 0x044F) or # Џ-я
        (cp >= 0x0451 and cp <= 0x045C) or # ё-ќ
        (cp >= 0x0490 and cp <= 0x0491) or # Ґ ґ
        (cp >= 0x2010 and cp <= 0x2027) or # General Punctuation
        (cp >= 0x2030 and cp <= 0x2035) or # ‰ ‱ ′ ″ ‴ ‵
        (cp >= 0x207F and cp <= 0x207F) or # ⁿ
        (cp >= 0x2081 and cp <= 0x2084) or # ₁₂₃₄
        (cp >= 0x2103 and cp <= 0x2103) or # ℃
        (cp >= 0x2105 and cp <= 0x2105) or # ☉
        (cp >= 0x2109 and cp <= 0x2109) or # ℉
        (cp >= 0x2120 and cp <= 0x2121) or # ℠ ℡
        (cp >= 0x2126 and cp <= 0x2126) or # Ω
        (cp >= 0x212B and cp <= 0x212B) or # Å
        (cp >= 0x2153 and cp <= 0x2154) or # ⅓ ⅔
        (cp >= 0x215B and cp <= 0x215E) or # ⅛ ⅜ ⅝ ⅞
        (cp >= 0x2160 and cp <= 0x216B) or # Ⅰ-Ⅻ (Roman numerals)
        (cp >= 0x2170 and cp <= 0x2179) or # ⅰ-ⅸ
        (cp >= 0x2300 and cp <= 0x2300) or # ⌀
        (cp >= 0x2302 and cp <= 0x2307) or # ⌂ ⌃ ⌄ ⌅ ⌆ ⌇
        (cp >= 0x230C and cp <= 0x2311) or # ⌌ ⌍ ⌎ ⌏ ⌐ ⌑
        (cp >= 0x2318 and cp <= 0x231B) or # ⌘ ⌙ ⌚ ⌛
        (cp >= 0x2320 and cp <= 0x2321) or # ⌠ ⌡
        (cp >= 0x2329 and cp <= 0x232A) or # 〈 〉
        (cp >= 0x23F4 and cp <= 0x23F9) or # ⏴-⏹
        (cp >= 0x23FA and cp <= 0x23FA) or # ⏺
        (cp >= 0x2460 and cp <= 0x24E9) or # ①-ⓩ, ①-㊿
        (cp >= 0x24EB and cp <= 0x254B) or # ⓫-㊿
        (cp >= 0x2550 and cp <= 0x2573) or # ═-╳
        (cp >= 0x2580 and cp <= 0x2595) or # ▀-▕
        (cp >= 0x25A0 and cp <= 0x25A1) or # ■ □
        (cp >= 0x25A3 and cp <= 0x25A9) or # ▣-▩
        (cp >= 0x25B2 and cp <= 0x25B3) or # ▲ △
        (cp >= 0x25B6 and cp <= 0x25B7) or # ▶ ▷
        (cp >= 0x25BC and cp <= 0x25BD) or # ▼ ▽
        (cp >= 0x25C0 and cp <= 0x25C1) or # ◀ ◁
        (cp >= 0x25C6 and cp <= 0x25C8) or # ◆ ◇ ◈
        (cp >= 0x25CA and cp <= 0x25CB) or # ◊ ○
        (cp >= 0x25CE and cp <= 0x25CF) or # ◎ ●
        (cp >= 0x25D8 and cp <= 0x25D8) or # ◘
        (cp >= 0x25E6 and cp <= 0x25E6) or # ◦
        (cp >= 0x2605 and cp <= 0x2606) or # ★ ☆
        (cp >= 0x260E and cp <= 0x260F) or # ☎ ☏
        (cp >= 0x261C and cp <= 0x261C) or # ☜
        (cp >= 0x261E and cp <= 0x261E) or # ☞
        (cp >= 0x2640 and cp <= 0x2640) or # ♀
        (cp >= 0x2642 and cp <= 0x2642) or # ♂
        (cp >= 0x2660 and cp <= 0x2661) or # ♠ ♡
        (cp >= 0x2663 and cp <= 0x2666) or # ♣ ♦
        (cp >= 0x2669 and cp <= 0x266A) or # ♩ ♪
        (cp >= 0x266C and cp <= 0x266C) or # ♬
        (cp >= 0x266F and cp <= 0x266F) or # ♯
        (cp >= 0x273D and cp <= 0x273D) or # ❍
        (cp >= 0x2756 and cp <= 0x2756) or # ❖
        (cp >= 0x27C5 and cp <= 0x27C6) or # ⧅ ⧆
        (cp >= 0x27E6 and cp <= 0x27EF) or # Mathematical Brackets
        (cp >= 0x2985 and cp <= 0x2986) or # ⦅ ⦆
        (cp >= 0x299B and cp <= 0x29AF) or # ⦛-⦯
        (cp >= 0x2B05 and cp <= 0x2B07) or # ⬅ ⬆ ⬇
        (cp >= 0x2B1B and cp <= 0x2B1C) or # ⬛ ⬜
        (cp >= 0x2B50 and cp <= 0x2B50) or # ⭐
        (cp >= 0x2B55 and cp <= 0x2B55) or # ⭕
        (cp >= 0x3000 and cp <= 0x3002) or # 。〃〈
        (cp >= 0x3004 and cp <= 0x3004) or # 〄
        (cp >= 0x3008 and cp <= 0x3011) or # 〈-】
        (cp >= 0x3014 and cp <= 0x301B) or # 〔-〙
        (cp >= 0x301D and cp <= 0x301F) or # 〝-〟
        (cp >= 0x3030 and cp <= 0x3030) or # 〰
        (cp >= 0x30FB and cp <= 0x30FB) or # ・
        (cp >= 0xFF0F and cp <= 0xFF0F) or # ／
        (cp >= 0xFF1C and cp <= 0xFF1E) or # ＜＝＞
        (cp >= 0xFF3C and cp <= 0xFF3C) or # ＼
        (cp >= 0xFF5E and cp <= 0xFF5E) or # ～
        (cp >= 0xFFE1 and cp <= 0xFFE1) or # ￠
        (cp >= 0xFFE5 and cp <= 0xFFE6):   # ￦ ￦
        return 2
    return 1

## Remove the last Unicode rune from a string (handles both full-width and half-width).
## Returns true if a character was removed, false if the string was empty.
proc removeLastRune*(s: var string): bool =
    var runes: seq[Rune] = @[]
    for r in s.runes:
        runes.add(r)
    if runes.len == 0:
        return false
    runes.setLen(runes.len - 1)
    s = ""
    for r in runes:
        s.add(r.toUTF8)
    return true

proc drawString*(buf: Buffer, x, y: int, str: string, style: Style = style()) =
    var currX = x
    for rune in str.runes:
        if currX >= buf.width: break
        # Skip escape characters (0x1B) to prevent ANSI injection
        if rune.int == 0x1B:
            continue
        let w = runeWidth(rune)
        if w == 2 and currX + 1 >= buf.width:
            break
            
        buf.setCell(currX, y, newCell(rune.toUTF8, style))
        if w == 2:
            buf.setCell(currX + 1, y, newCell("", style))
        currX += w

# =============================================================================
# Border styles for drawBox
# =============================================================================
type BorderStyle* = enum
    bsSingle,   ## ┌┐└┘─│ single line
    bsDouble,   ## ╔╗╚╝═║ double line
    bsRounded,  ## ╭╮╰╯─│ rounded (default)
    bsBold      ## ┏┓┗┛━┃ bold

## Draw a box (rectangle) into the buffer.
## x, y: top-left corner
## w, h: width and height (including borders)
## style: border and fill style
## borderType: border style type
##
## Steps:
##   1. Place corner characters
##   2. Draw horizontal edges
##   3. Draw vertical edges
##   4. Fill interior with spaces
proc drawBox*(buf: Buffer, x, y, w, h: int, style: Style = style(),
              borderType: BorderStyle = bsRounded) =
    # Select characters based on border style
    # (tl=top-left, tr=top-right, bl=bottom-left, br=bottom-right, hz=horizontal, vt=vertical)
    let (tl, tr, bl, br, hz, vt) = case borderType
    of bsRounded: ("╭", "╮", "╰", "╯", "─", "│")
    of bsDouble:  ("╔", "╗", "╚", "╝", "═", "║")
    of bsBold:    ("┏", "┓", "┗", "┛", "━", "┃")
    else:         ("┌", "┐", "└", "┘", "─", "│")

    # Draw corners
    buf.setCell(x, y, newCell(tl, style))                    # top-left
    buf.setCell(x + w - 1, y, newCell(tr, style))            # top-right
    buf.setCell(x, y + h - 1, newCell(bl, style))            # bottom-left
    buf.setCell(x + w - 1, y + h - 1, newCell(br, style))   # bottom-right

    # Draw horizontal lines (top and bottom edges)
    for cx in (x + 1) ..< (x + w - 1):
        buf.setCell(cx, y, newCell(hz, style))
        buf.setCell(cx, y + h - 1, newCell(hz, style))

    # Draw vertical lines (left and right edges)
    for cy in (y + 1) ..< (y + h - 1):
        buf.setCell(x, cy, newCell(vt, style))
        buf.setCell(x + w - 1, cy, newCell(vt, style))

    # Fill interior with spaces (to reflect background color)
    for cy in (y + 1) ..< (y + h - 1):
        for cx in (x + 1) ..< (x + w - 1):
            buf.setCell(cx, cy, newCell(" ", style))
