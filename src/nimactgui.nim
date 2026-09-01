## =============================================================================
## nimactgui.nim — GUI ライブラリのエントリポイント
##
## GUI 機能を使いたい場合は `import nimactgui` する
## TUI との分離を保つため、別ファイルとして提供
##
## 使用例:
##   import nimactgui
##   let app = newApp("My App", 800, 600)
##   app.runSimple(proc(): Widget =
##     scaffold(
##       appBar: AppBarConfig(title: "Hello"),
##       body: center(
##         text("Hello, GUI!", textStyle(size: 32, color: colWhite))
##       )
##     )
##   )
## =============================================================================

import nimact/gui/app
import nimact/gui/widget
import nimact/core/graphics
import nimact/core/text

export app, widget, graphics, text
