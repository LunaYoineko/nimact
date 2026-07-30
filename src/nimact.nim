## =============================================================================
## nimact.nim — ライブラリのエントリポイント
##
## ユーザーが `import nimact` とした際に、このファイルが読み込まれる
## 全ての公開APIをここから再エクスポートする
##
## ユーザーが使うことになる型・関数:
##   App, newApp, run, onKey, quit        (app.nim)
##   Widget, label, vbox, hbox, center,   (widget.nim)
##   header, footer, progress, separator,
##   spacer
##   Color, Style, style, rgb,            (buffer.nim)
##   color constants (colBlue, etc.)
##   EventBus, newEventBus                (event.nim)
##   KeyKind, KeyEvent                    (input.nim via event.nim)
##
## 使用例:
##   import nimact
##   let app = newApp()
##   app.onKey('q', proc() = app.quit())
##   waitFor app.run(proc(): Widget = label("Hello"))
## =============================================================================

import nimact/app
import nimact/components/widget
import nimact/core/buffer
import nimact/core/event
import nimact/core/term

export app, widget, buffer, event, term
