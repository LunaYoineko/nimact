import std/unittest
import std/unicode
import std/strutils
import nimact/core/buffer
import nimact/components/widget

suite "Buffer creation & initialization":

  test "newBuffer creates correct dimensions":
    let buf = newBuffer(80, 24)
    check buf.width == 80
    check buf.height == 24
    check buf.cells.len == 80 * 24

  test "newBuffer initializes all cells to space":
    let buf = newBuffer(5, 3)
    for y in 0 ..< 3:
      for x in 0 ..< 5:
        check buf.getCell(x, y).ch == " "

  test "newBuffer with 1x1":
    let buf = newBuffer(1, 1)
    check buf.width == 1
    check buf.height == 1
    check buf.getCell(0, 0).ch == " "

suite "Cell operations":

  test "setCell and getCell round-trip":
    let buf = newBuffer(10, 10)
    let s = style(fg = colRed, bg = colBlue, bold = true)
    buf.setCell(3, 5, newCell("X", s))
    let c = buf.getCell(3, 5)
    check c.ch == "X"
    check c.style.fg.r == 224
    check c.style.bg.b == 239
    check c.style.bold == true

  test "setCell ignores out-of-bounds coordinates":
    let buf = newBuffer(5, 5)
    buf.setCell(-1, 0, newCell("X"))
    buf.setCell(0, -1, newCell("X"))
    buf.setCell(5, 0, newCell("X"))
    buf.setCell(0, 5, newCell("X"))
    # All cells should remain as default space
    for y in 0 ..< 5:
      for x in 0 ..< 5:
        check buf.getCell(x, y).ch == " "

  test "getCell returns default for out-of-bounds":
    let buf = newBuffer(5, 5)
    check buf.getCell(-1, 0).ch == " "
    check buf.getCell(0, -1).ch == " "
    check buf.getCell(5, 0).ch == " "
    check buf.getCell(0, 5).ch == " "
    check buf.getCell(100, 100).ch == " "

suite "Color & Style":

  test "rgb creates correct color":
    let c = rgb(10, 20, 30)
    check c.r == 10
    check c.g == 20
    check c.b == 30
    check c.isDefault == false

  test "defaultColor has isDefault flag":
    let c = defaultColor()
    check c.isDefault == true

  test "style with all parameters":
    let s = style(fg = colGreen, bg = colRed, bold = true, dim = true,
                   italic = true, underline = true, reverse = true)
    check s.bold == true
    check s.dim == true
    check s.italic == true
    check s.underline == true
    check s.reverse == true

  test "style defaults are all false/default":
    let s = style()
    check s.bold == false
    check s.fg.isDefault == true
    check s.bg.isDefault == true

suite "runeWidth":

  test "ASCII characters are width 1":
    check runeWidth("A".toRunes[0]) == 1
    check runeWidth("z".toRunes[0]) == 1
    check runeWidth("0".toRunes[0]) == 1
    check runeWidth(" ".toRunes[0]) == 1

  test "CJK characters are width 2":
    check runeWidth("漢".toRunes[0]) == 2
    check runeWidth("日".toRunes[0]) == 2
    check runeWidth("ア".toRunes[0]) == 2
    check runeWidth("가".toRunes[0]) == 2

  test "fullwidth Latin characters are width 2":
    check runeWidth("Ａ".toRunes[0]) == 2
    check runeWidth("ｚ".toRunes[0]) == 2

  test "emoji are width 2":
    check runeWidth("😀".toRunes[0]) == 2

  test "ambiguous-width characters are width 2":
    check runeWidth("♠".toRunes[0]) == 2
    check runeWidth("♥".toRunes[0]) == 2
    check runeWidth("★".toRunes[0]) == 2

suite "drawString":

  test "drawString places ASCII correctly":
    let buf = newBuffer(20, 3)
    buf.drawString(0, 0, "Hello", style(fg = colGreen))
    check buf.getCell(0, 0).ch == "H"
    check buf.getCell(1, 0).ch == "e"
    check buf.getCell(2, 0).ch == "l"
    check buf.getCell(3, 0).ch == "l"
    check buf.getCell(4, 0).ch == "o"

  test "drawString with offset":
    let buf = newBuffer(20, 3)
    buf.drawString(5, 1, "Hi", style(fg = colBlue))
    check buf.getCell(5, 1).ch == "H"
    check buf.getCell(6, 1).ch == "i"

  test "drawString with CJK occupies 2 cells":
    let buf = newBuffer(20, 3)
    buf.drawString(0, 0, "AB", style())
    # A is 1-wide, B is 1-wide
    check buf.getCell(0, 0).ch == "A"
    check buf.getCell(1, 0).ch == "B"

  test "drawString with CJK 2-wide char fills second cell":
    let buf = newBuffer(20, 3)
    buf.drawString(0, 0, "日月", style(fg = colRed))
    check buf.getCell(0, 0).ch == "日"
    check buf.getCell(1, 0).ch.len == 0  # 2nd cell is empty dummy
    check buf.getCell(2, 0).ch == "月"
    check buf.getCell(3, 0).ch.len == 0  # 2nd cell is empty dummy

  test "drawString with ambiguous-width char fills second cell":
    let buf = newBuffer(20, 3)
    buf.drawString(0, 0, "♠♥", style(fg = colWhite))
    check buf.getCell(0, 0).ch == "♠"
    check buf.getCell(1, 0).ch.len == 0
    check buf.getCell(2, 0).ch == "♥"
    check buf.getCell(3, 0).ch.len == 0

  test "drawString clips at buffer width":
    let buf = newBuffer(5, 1)
    buf.drawString(0, 0, "Hello World", style())
    check buf.getCell(0, 0).ch == "H"
    check buf.getCell(4, 0).ch == "o"
    # Should not write beyond buffer width

  test "drawString skips 2-wide char when only 1 cell remains":
    let buf = newBuffer(3, 1)
    buf.drawString(0, 0, "漢字", style())
    check buf.getCell(0, 0).ch == "漢"
    check buf.getCell(1, 0).ch.len == 0  # dummy
    # 3rd cell: "字" needs 2 cells but only 1 remains, so it's skipped
    check buf.getCell(2, 0).ch == " "

  test "drawString with empty string does nothing":
    let buf = newBuffer(5, 1)
    buf.setCell(2, 0, newCell("X"))
    buf.drawString(0, 0, "", style())
    check buf.getCell(2, 0).ch == "X"

  test "drawString applies style to all cells":
    let buf = newBuffer(10, 1)
    let s = style(fg = colRed)
    buf.drawString(0, 0, "ABC", s)
    check buf.getCell(0, 0).style.fg.r == 224
    check buf.getCell(1, 0).style.fg.r == 224
    check buf.getCell(2, 0).style.fg.r == 224

suite "drawBox":

  test "drawBox renders corners":
    let buf = newBuffer(10, 5)
    buf.drawBox(0, 0, 10, 5, style(), bsRounded)
    check buf.getCell(0, 0).ch == "╭"
    check buf.getCell(9, 0).ch == "╮"
    check buf.getCell(0, 4).ch == "╰"
    check buf.getCell(9, 4).ch == "╯"

  test "drawBox renders horizontal edges":
    let buf = newBuffer(10, 5)
    buf.drawBox(0, 0, 10, 5, style(), bsRounded)
    check buf.getCell(1, 0).ch == "─"
    check buf.getCell(8, 0).ch == "─"
    check buf.getCell(1, 4).ch == "─"
    check buf.getCell(8, 4).ch == "─"

  test "drawBox renders vertical edges":
    let buf = newBuffer(10, 5)
    buf.drawBox(0, 0, 10, 5, style(), bsRounded)
    check buf.getCell(0, 1).ch == "│"
    check buf.getCell(0, 3).ch == "│"
    check buf.getCell(9, 1).ch == "│"
    check buf.getCell(9, 3).ch == "│"

  test "drawBox fills interior with spaces":
    let buf = newBuffer(10, 5)
    buf.drawBox(0, 0, 10, 5, style(fg = colBlue), bsRounded)
    check buf.getCell(1, 1).ch == " "
    check buf.getCell(5, 2).ch == " "

  test "drawBox double border style":
    let buf = newBuffer(8, 4)
    buf.drawBox(0, 0, 8, 4, style(), bsDouble)
    check buf.getCell(0, 0).ch == "╔"
    check buf.getCell(7, 0).ch == "╗"
    check buf.getCell(0, 3).ch == "╚"
    check buf.getCell(7, 3).ch == "╝"
    check buf.getCell(1, 0).ch == "═"
    check buf.getCell(0, 1).ch == "║"

  test "drawBox bold border style":
    let buf = newBuffer(8, 4)
    buf.drawBox(0, 0, 8, 4, style(), bsBold)
    check buf.getCell(0, 0).ch == "┏"
    check buf.getCell(7, 0).ch == "┓"
    check buf.getCell(1, 0).ch == "━"
    check buf.getCell(0, 1).ch == "┃"

  test "drawBox at offset position":
    let buf = newBuffer(20, 10)
    buf.drawBox(5, 3, 6, 4, style(), bsRounded)
    check buf.getCell(5, 3).ch == "╭"
    check buf.getCell(10, 3).ch == "╮"
    check buf.getCell(5, 6).ch == "╰"
    check buf.getCell(10, 6).ch == "╯"

suite "Footer render":

  test "footer renders at the bottom of the buffer":
    let width = 80
    let height = 24
    let buf = newBuffer(width, height)
    let f = footer("Footer Text")
    f.render(buf, 0, height - 1, width, 1)
    var lineText = ""
    for x in 0 ..< width:
      lineText &= buf.getCell(x, height - 1).ch
    check "Footer Text" in lineText

  test "header renders at the top of the buffer":
    let width = 80
    let buf = newBuffer(width, 5)
    let h = header("My App", fg = colWhite, bg = colBlue)
    h.render(buf, 0, 0, width, 1)
    var lineText = ""
    for x in 0 ..< width:
      lineText &= buf.getCell(x, 0).ch
    check "My App" in lineText

suite "Separator render":

  test "separator renders horizontal line":
    let buf = newBuffer(20, 1)
    let sep = separator(fg = colTextMuted)
    sep.render(buf, 0, 0, 20, 1)
    for x in 0 ..< 20:
      check buf.getCell(x, 0).ch == "─"

suite "Progress render":

  test "progress renders filled and empty blocks":
    let buf = newBuffer(20, 1)
    let p = progress(0.5, max = 1.0, fg = colGreen)
    p.render(buf, 0, 0, 20, 1)
    # Bar width = 20 - 4 = 16, 50% filled = 8 blocks
    var filledCount = 0
    var emptyCount = 0
    for x in 2 ..< 18:
      if buf.getCell(x, 0).ch == "█":
        filledCount += 1
      elif buf.getCell(x, 0).ch == "░":
        emptyCount += 1
    check filledCount == 8
    check emptyCount == 8

suite "Mixed content rendering":

  test "mixed ASCII and CJK in same line":
    let buf = newBuffer(30, 1)
    buf.drawString(0, 0, "Hi漢", style())
    check buf.getCell(0, 0).ch == "H"
    check buf.getCell(1, 0).ch == "i"
    check buf.getCell(2, 0).ch == "漢"
    check buf.getCell(3, 0).ch.len == 0  # CJK 2nd cell

  test "card notation with suit and rank":
    let buf = newBuffer(30, 1)
    buf.drawString(0, 0, "[♠A]", style(fg = colWhite))
    check buf.getCell(0, 0).ch == "["
    check buf.getCell(1, 0).ch == "♠"
    check buf.getCell(2, 0).ch.len == 0  # suit 2nd cell
    check buf.getCell(3, 0).ch == "A"
    check buf.getCell(4, 0).ch == "]"

suite "newBuffer edge cases":

  test "newBuffer returns nil for zero width":
    check newBuffer(0, 10) == nil

  test "newBuffer returns nil for zero height":
    check newBuffer(10, 0) == nil

  test "newBuffer returns nil for negative dimensions":
    check newBuffer(-1, 10) == nil
    check newBuffer(10, -1) == nil

suite "ANSI injection prevention":

  test "drawString skips ESC character (0x1B)":
    let buf = newBuffer(10, 1)
    # String contains ESC followed by [2J (screen clear sequence)
    # ESC is stripped, but [2J chars are drawn as literal text
    buf.drawString(0, 0, "A\x1B[2JB", style())
    check buf.getCell(0, 0).ch == "A"
    check buf.getCell(1, 0).ch == "["
    check buf.getCell(2, 0).ch == "2"
    check buf.getCell(3, 0).ch == "J"
    check buf.getCell(4, 0).ch == "B"

  test "drawString skips standalone ESC":
    let buf = newBuffer(10, 1)
    buf.drawString(0, 0, "\x1B", style())
    # No visible characters should be written
    check buf.getCell(0, 0).ch == " "

  test "drawString handles mixed content with ESC":
    let buf = newBuffer(10, 1)
    buf.drawString(0, 0, "Hi\x1B[31mRed", style())
    check buf.getCell(0, 0).ch == "H"
    check buf.getCell(1, 0).ch == "i"
    # After stripping ESC: [31mRed is drawn as literal text
    check buf.getCell(2, 0).ch == "["
    check buf.getCell(3, 0).ch == "3"
    check buf.getCell(4, 0).ch == "1"
    check buf.getCell(5, 0).ch == "m"
    check buf.getCell(6, 0).ch == "R"
    check buf.getCell(7, 0).ch == "e"
    check buf.getCell(8, 0).ch == "d"

suite "runeWidth zero-width characters":

  test "combining diacritical mark has width 0":
    check runeWidth("\u0300".toRunes[0]) == 0  # grave accent combining

  test "variation selector has width 0":
    check runeWidth("\uFE0E".toRunes[0]) == 0  # text presentation

  test "ZWJ has width 0":
    check runeWidth("\u200D".toRunes[0]) == 0

  test "zero-width space has width 0":
    check runeWidth("\u200B".toRunes[0]) == 0

suite "runeWidth extended emoji":

  test "supplemental emoji has width 2":
    check runeWidth(Rune(0x1F900)) == 2  # 🤀

  test "skin tone modifier has width 2":
    check runeWidth(Rune(0x1F3FB)) == 2  # 🏻

  test "regional indicator has width 2":
    check runeWidth(Rune(0x1F1FA)) == 2  # 🇺
