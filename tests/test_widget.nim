import std/unittest
import nimact

suite "label measure":

  test "label measures ASCII text width":
    let lw = label("Hello")
    let (ww, hh) = lw.measure(80)
    check ww == 5

  test "label measures CJK text width":
    let lw = label("日本語")
    let (ww, hh) = lw.measure(80)
    check ww == 6  # 3 chars * 2 width each

  test "label measures mixed text width":
    let lw = label("Hi漢")
    let (ww, hh) = lw.measure(80)
    check ww == 4  # H(1) + i(1) + 漢(2)

  test "label measures empty string":
    let lw = label("")
    let (ww, hh) = lw.measure(80)
    check ww == 0

  test "label height is always 1":
    let lw = label("anything")
    let (ww, hh) = lw.measure(80)
    check hh == 1

  test "label render places characters correctly":
    let lw = label("AB", fg = colRed)
    let buf = newBuffer(10, 3)
    lw.render(buf, 2, 1, 10, 1)
    check buf.getCell(2, 1).ch == "A"
    check buf.getCell(3, 1).ch == "B"

  test "label render with CJK characters":
    let lw = label("漢字", fg = colWhite)
    let buf = newBuffer(10, 3)
    lw.render(buf, 0, 0, 10, 1)
    check buf.getCell(0, 0).ch == "漢"
    check buf.getCell(1, 0).ch.len == 0
    check buf.getCell(2, 0).ch == "字"
    check buf.getCell(3, 0).ch.len == 0

  test "label inherits parent bg style":
    let lw = label("Hi")
    let buf = newBuffer(10, 1)
    let parentStyle = style(bg = colRed)
    lw.render(buf, 0, 0, 10, 1, parentStyle)
    check buf.getCell(0, 0).style.bg.r == 224

suite "header & footer":

  test "header widget kind":
    let hd = header("Title")
    check hd.kind == wkHeader

  test "footer widget kind":
    let ft = footer("Info")
    check ft.kind == wkFooter

  test "header measure returns availableWidth":
    let hd = header("App")
    let (ww, hh) = hd.measure(80)
    check ww == 80
    check hh == 1

  test "footer measure returns availableWidth":
    let ft = footer("Status")
    let (ww, hh) = ft.measure(80)
    check ww == 80
    check hh == 1

  test "header render fills full width with bg":
    let hd = header("App", fg = colBgDark, bg = colWhite)
    let buf = newBuffer(30, 1)
    hd.render(buf, 0, 0, 30, 1)
    check buf.getCell(0, 0).style.bg.r == 255
    check buf.getCell(29, 0).style.bg.r == 255

  test "footer render fills full width with bg":
    let ft = footer("Status", fg = colBgDark, bg = colWhite)
    let buf = newBuffer(30, 1)
    ft.render(buf, 0, 0, 30, 1)
    check buf.getCell(0, 0).style.bg.r == 255
    check buf.getCell(29, 0).style.bg.r == 255

suite "progress widget":

  test "progress measure returns availableWidth x 1":
    let pw = progress(0.5, max = 1.0)
    let (ww, hh) = pw.measure(20)
    check ww == 20
    check hh == 1

  test "progress 0% shows no filled blocks":
    let buf = newBuffer(20, 1)
    let p = progress(0.0, max = 1.0)
    p.render(buf, 0, 0, 20, 1)
    var filledCount = 0
    for x in 2 ..< 18:
      if buf.getCell(x, 0).ch == "█":
        filledCount += 1
    check filledCount == 0

  test "progress 100% shows all filled blocks":
    let buf = newBuffer(20, 1)
    let p = progress(1.0, max = 1.0)
    p.render(buf, 0, 0, 20, 1)
    var filledCount = 0
    for x in 2 ..< 18:
      if buf.getCell(x, 0).ch == "█":
        filledCount += 1
    check filledCount == 16

  test "progress 50% shows half filled blocks":
    let buf = newBuffer(20, 1)
    let p = progress(0.5, max = 1.0)
    p.render(buf, 0, 0, 20, 1)
    var filledCount = 0
    var emptyCount = 0
    for x in 2 ..< 18:
      if buf.getCell(x, 0).ch == "█":
        filledCount += 1
      elif buf.getCell(x, 0).ch == "░":
        emptyCount += 1
    check filledCount == 8
    check emptyCount == 8

suite "separator widget":

  test "separator measure returns availableWidth x 1":
    let sw = separator(fg = colTextMuted)
    let (ww, hh) = sw.measure(40)
    check ww == 40
    check hh == 1

  test "separator render fills full width with ─":
    let buf = newBuffer(40, 1)
    let s = separator(fg = colTextMuted)
    s.render(buf, 0, 0, 40, 1)
    for x in 0 ..< 40:
      check buf.getCell(x, 0).ch == "─"

suite "spacer widget":

  test "spacer measure returns (0, height)":
    let sp = spacer(3)
    let (ww, hh) = sp.measure(20)
    check ww == 0
    check hh == 3

  test "spacer render does not write visible characters":
    let buf = newBuffer(10, 3)
    buf.setCell(5, 1, newCell("X"))
    let s = spacer(3)
    s.render(buf, 0, 0, 10, 3)
    check buf.getCell(5, 1).ch == "X"

suite "vbox widget":

  test "vbox measure aggregates children heights":
    let va = label("AAA")  # 3x1
    let vb = label("BBBBBB")  # 6x1
    let v = vbox(va, vb)
    let (ww, hh) = v.measure(80)
    check ww == 6  # max width
    check hh == 2  # 1 + 1

  test "vbox with gap adds spacing":
    let va = label("AA")
    let vb = label("BB")
    let v = vbox(1, va, vb)
    let (ww, hh) = v.measure(80)
    check hh == 3  # 1 + 1(gap) + 1

  test "vbox with style variant":
    let va = label("AA")
    let vb = label("BB")
    let v = vbox(0, style(fg = colRed), va, vb)
    let (ww, hh) = v.measure(80)
    check hh == 2

  test "vbox render places children sequentially with centering":
    let va = label("Top", fg = colRed)
    let vb = label("Bot", fg = colBlue)
    let v = vbox(va, vb)
    let buf = newBuffer(20, 6)
    # height=6, childrenH=2 -> offsetY = (6-2)/2 = 2
    v.render(buf, 0, 0, 20, 6)
    check buf.getCell(0, 2).ch == "T"
    check buf.getCell(0, 3).ch == "B"

  test "vbox with header and footer":
    let hd = header("Title")
    let ft = footer("Info")
    let v = vbox(hd, ft)
    let (ww, hh) = v.measure(80)
    check hh == 2

  test "vbox with separator between elements":
    let l1 = label("A")
    let sep = separator(fg = colTextMuted)
    let l2 = label("B")
    let v = vbox(l1, sep, l2)
    let (ww, hh) = v.measure(80)
    check hh == 3

  test "vbox with 3 children":
    let va = label("A")
    let vb = label("B")
    let vc = label("C")
    let v = vbox(va, vb, vc)
    let (ww, hh) = v.measure(80)
    check hh == 3
    check ww == 1

suite "hbox widget":

  test "hbox measure aggregates children widths":
    let ha = label("AA")  # 2x1
    let hb = label("BB")  # 2x1
    let h = hbox(ha, hb)
    let (ww, hh) = h.measure(80)
    check ww == 4  # 2 + 2
    check hh == 1

  test "hbox with gap adds spacing":
    let ha = label("AA")
    let hb = label("BB")
    let h = hbox(1, ha, hb)
    let (ww, hh) = h.measure(80)
    check ww == 5  # 2 + 1(gap) + 2

  test "hbox with style variant":
    let ha = label("AA")
    let hb = label("BB")
    let h = hbox(0, style(fg = colRed), ha, hb)
    let (ww, hh) = h.measure(80)
    check ww == 4

  test "hbox render places children horizontally with centering":
    let ha = label("AA", fg = colRed)
    let hb = label("BB", fg = colBlue)
    let h = hbox(ha, hb)
    let buf = newBuffer(20, 1)
    # width=20, childrenW=4 -> offsetX = (20-4)/2 = 8
    h.render(buf, 0, 0, 20, 1)
    check buf.getCell(8, 0).ch == "A"
    check buf.getCell(9, 0).ch == "A"
    check buf.getCell(10, 0).ch == "B"
    check buf.getCell(11, 0).ch == "B"

  test "hbox with gap renders space between children with centering":
    let ha = label("A")
    let hb = label("B")
    let h = hbox(2, ha, hb)
    let buf = newBuffer(10, 1)
    # width=10, childrenW=1+2+1=4 -> offsetX = (10-4)/2 = 3
    h.render(buf, 0, 0, 10, 1)
    check buf.getCell(3, 0).ch == "A"
    check buf.getCell(4, 0).ch == " "
    check buf.getCell(5, 0).ch == " "
    check buf.getCell(6, 0).ch == "B"

  test "hbox with 3 children":
    let ha = label("A")
    let hb = label("B")
    let hc = label("C")
    let h = hbox(ha, hb, hc)
    let (ww, hh) = h.measure(80)
    check ww == 3
    check hh == 1

  test "hbox style variant measures correctly":
    let h2 = hbox(label("AB"), label("CD"))
    let (ww, hh) = h2.measure(80)
    check ww == 4

suite "center widget":

  test "center measure returns given dimensions":
    let c = center(30, 5, label("Hi"))
    let (ww, hh) = c.measure(80)
    check ww == 30
    check hh == 5

  test "center render places child at centered position":
    # center(10,3) in a 20x5 parent: offsetX=(20-10)/2=5, offsetY=(5-3)/2=1
    let c = center(10, 3, label("X"))
    let buf = newBuffer(20, 5)
    c.render(buf, 0, 0, 20, 5)
    check buf.getCell(5, 1).ch == "X"

  test "center render with 2-character label":
    let c = center(10, 3, label("AB"))
    let buf = newBuffer(20, 5)
    c.render(buf, 0, 0, 20, 5)
    check buf.getCell(5, 1).ch == "A"
    check buf.getCell(6, 1).ch == "B"

  test "center with multiple children stacks vertically":
    let c = center(10, 3, label("A"), label("B"))
    let buf = newBuffer(20, 5)
    c.render(buf, 0, 0, 20, 5)
    check buf.getCell(5, 1).ch == "A"
    check buf.getCell(5, 2).ch == "B"

suite "box widget":

  test "box measure includes borders":
    let bw = box(10, 5, style(), bsRounded, label("Hi"))
    let (ww, hh) = bw.measure(80)
    check ww == 10
    check hh == 5

  test "box render draws border":
    let b = box(8, 4, style(), bsRounded)
    let buf = newBuffer(8, 4)
    b.render(buf, 0, 0, 8, 4)
    check buf.getCell(0, 0).ch == "╭"
    check buf.getCell(7, 0).ch == "╮"
    check buf.getCell(0, 3).ch == "╰"
    check buf.getCell(7, 3).ch == "╯"

  test "box render with child label":
    let b = box(10, 3, style(), bsRounded, label("Hi"))
    let buf = newBuffer(10, 3)
    b.render(buf, 0, 0, 10, 3)
    # Border at edges
    check buf.getCell(0, 0).ch == "╭"
    # Child "Hi" rendered at x=1 (inside border), y=1 (middle row)
    check buf.getCell(1, 1).ch == "H"
    check buf.getCell(2, 1).ch == "i"

  test "box with double border style":
    let b = box(6, 4, style(), bsDouble)
    let buf = newBuffer(6, 4)
    b.render(buf, 0, 0, 6, 4)
    check buf.getCell(0, 0).ch == "╔"
    check buf.getCell(5, 0).ch == "╗"
    check buf.getCell(0, 3).ch == "╚"
    check buf.getCell(5, 3).ch == "╝"

  test "box with bold border style":
    let b = box(6, 4, style(), bsBold)
    let buf = newBuffer(6, 4)
    b.render(buf, 0, 0, 6, 4)
    check buf.getCell(0, 0).ch == "┏"
    check buf.getCell(5, 0).ch == "┓"
    check buf.getCell(0, 3).ch == "┗"
    check buf.getCell(5, 3).ch == "┛"

  test "box interior is filled with spaces":
    let b = box(6, 4, style(fg = colGreen), bsRounded)
    let buf = newBuffer(6, 4)
    b.render(buf, 0, 0, 6, 4)
    check buf.getCell(1, 1).ch == " "
    check buf.getCell(4, 2).ch == " "

  test "box with single border style":
    let b = box(6, 4, style(), bsSingle)
    let buf = newBuffer(6, 4)
    b.render(buf, 0, 0, 6, 4)
    check buf.getCell(0, 0).ch == "┌"
    check buf.getCell(5, 0).ch == "┐"
    check buf.getCell(0, 3).ch == "└"
    check buf.getCell(5, 3).ch == "┘"

suite "widget kind field":

  test "label kind is wkLabel":
    check label("X").kind == wkLabel

  test "separator kind is wkSeparator":
    check separator(fg = colTextMuted).kind == wkSeparator

  test "spacer kind is wkSpacer":
    check spacer(5).kind == wkSpacer

  test "vbox kind is wkVBox":
    check vbox(label("A")).kind == wkVBox

  test "hbox kind is wkHBox":
    check hbox(label("A")).kind == wkHBox

  test "center kind is wkCenter":
    check center(5, 5, label("A")).kind == wkCenter

  test "box kind is wkBox":
    check box(5, 5, style(), bsRounded, label("A")).kind == wkBox

  test "progress kind is wkProgress":
    check progress(0.5).kind == wkProgress

  test "header kind is wkHeader":
    check header("X").kind == wkHeader

suite "nested layouts":

  test "vbox inside hbox measure":
    let va = label("AA")   # 2x1
    let vb = label("BBBB") # 4x1
    let v = vbox(va, vb)   # max w=4, h=2
    let left = label("L")   # 1x1
    let h = hbox(left, v)   # w=1+4=5, h=max(1,2)=2
    let (ww, hh) = h.measure(80)
    check ww == 5
    check hh == 2

  test "hbox inside vbox measure":
    let ha = hbox(label("A"), label("BB"))  # 3x1
    let left = label("C")                    # 1x1
    let v = vbox(ha, left)
    let (ww, hh) = v.measure(80)
    check ww == 3  # max(3, 1)
    check hh == 2

  test "deeply nested measure":
    let inner = center(10, 5, label("X"))
    let outer = vbox(inner, label("Y"))
    let (ww, hh) = outer.measure(80)
    check ww == 10
    check hh == 6  # 5 + 1

  test "box containing vbox containing labels":
    let inner = vbox(label("A"), label("B"))
    let bw = box(10, 5, style(), bsRounded, inner)
    let (ww, hh) = bw.measure(80)
    check ww == 10
    check hh == 5

  test "hbox with center children":
    let c = center(10, 3, label("X"))
    let h = hbox(label("Hi"), c)
    let (ww, hh) = h.measure(80)
    check ww == 12  # 2 + 10
    check hh == 3   # max(1, 3)
