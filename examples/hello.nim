## =============================================================================
## examples/hello.nim
## nimact の最小サンプル: Hello World
##
## 操作方法:
##   Q キー: アプリケーションを終了
## =============================================================================

import std/asyncdispatch
import ../src/nimact

let app = newApp()

proc build(): Widget =
  vbox(
    header("Hello App", fg = colWhite, bg = colBlue, bold = true),
    center(40, 5,
      label("Hello, Nimact!", fg = colGreen, bold = true)
    ),
    footer("Q: Quit", fg = colTextMuted, bg = colBgDark)
  )

app.onKey('q', proc() = app.quit())
app.onKey('Q', proc() = app.quit())

waitFor app.run(build)
