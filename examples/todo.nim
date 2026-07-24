## =============================================================================
## examples/todo.nim
## nimact の上級サンプル: インタラクティブ TODO リスト
##
## このサンプルは以下の機能をデモしている:
##   - ↑↓ による項目選択 (インデックス管理)
##   - Space による項目の追加 / 完了トグル
##   - Backspace による項目の削除
##   - ハイライト表示による選択中項目の強調
##   - 動的なプログレスバー (完了率)
##
## 操作方法:
##   ↑ / ↓ キー: 項目の選択移動
##   SPACE キー:   完了トグル (追加モード中は入力確定)
##   Enter:        追加モード開始 / 入力確定
##   Backspace:    選択中の項目を削除 (または入力中の1文字削除)
##   Esc:          追加モードキャンセル / アプリ終了
##   Q キー:       アプリケーションを終了
## =============================================================================

import std/asyncdispatch
import ../src/nimact

# =============================================================================
# アプリケーションの状態
# =============================================================================

type
  TodoItem = object
    text: string
    done: bool

var
  todos: seq[TodoItem] = @[
    TodoItem(text: "Learn Nim basics", done: true),
    TodoItem(text: "Build a TUI app", done: true),
    TodoItem(text: "Add interactive features", done: false),
    TodoItem(text: "Publish to GitHub", done: false),
    TodoItem(text: "Write documentation", done: false),
  ]
  cursor = 0          ## 選択中のインデックス
  addingMode = false  ## 追加モードフラグ
  inputBuffer = ""    ## 入力バッファ

let app = newApp()

# =============================================================================
# ヘルパー関数
# =============================================================================

proc completedCount(): int =
  for t in todos:
    if t.done: result.inc

proc totalCount(): int =
  todos.len

# =============================================================================
# ウィジェットツリーの構築
# =============================================================================

proc build(): Widget =
  let progressVal = if totalCount() > 0:
    completedCount().float / totalCount().float
  else:
    0.0

  var todoWidgets: seq[Widget]

  todoWidgets.add(label(" [ TODO List ] ", fg = colPurple, bold = true))
  todoWidgets.add(spacer(1))

  for i, item in todos:
    let prefix = if item.done: "[x] " else: "[ ] "
    let color = if item.done: colTextMuted
                elif i == cursor: colGreen
                else: colText
    let marker = if i == cursor: "> " else: "  "
    todoWidgets.add(label(marker & prefix & item.text, fg = color, bold = (i == cursor)))

  if todos.len == 0:
    todoWidgets.add(label("  (No items)", fg = colTextMuted))

  todoWidgets.add(spacer(1))
  todoWidgets.add(separator(fg = colTextMuted))
  todoWidgets.add(label("  Done: " & $completedCount() & "/" & $totalCount(), fg = colText))
  todoWidgets.add(progress(progressVal, max = 1.0, fg = colGreen))

  if addingMode:
    todoWidgets.add(spacer(1))
    todoWidgets.add(label("  > " & inputBuffer & "_", fg = colYellow, bold = true))
    todoWidgets.add(label("    Enter: confirm | Esc: cancel", fg = colTextMuted))

  vbox(
    header(" Todo App ", fg = colWhite, bg = colBlue, bold = true),
    center(50, todos.len + 14, todoWidgets),
    footer(" ↑↓: Select | SPACE: Toggle | Enter: Add | Backspace: Delete | Q: Quit ", fg = colTextMuted, bg = colBgDark)
  )

# =============================================================================
# キーイベントハンドラの登録
# =============================================================================

app.onKey(nkUp, proc() =
  if not addingMode and todos.len > 0:
    cursor = (cursor - 1 + todos.len) mod todos.len
)

app.onKey(nkDown, proc() =
  if not addingMode and todos.len > 0:
    cursor = (cursor + 1) mod todos.len
)

app.onKey(' ', proc() =
  if addingMode:
    if inputBuffer.len < 40: inputBuffer.add(' ')
  else:
    if todos.len > 0:
      todos[cursor].done = not todos[cursor].done
)

app.onKey(nkEnter, proc() =
  if addingMode:
    if inputBuffer.len > 0:
      todos.add(TodoItem(text: inputBuffer, done: false))
      inputBuffer = ""
      addingMode = false
      cursor = todos.len - 1
  else:
    addingMode = true
    inputBuffer = ""
)

app.onKey(nkEscape, proc() =
  if addingMode:
    addingMode = false
    inputBuffer = ""
  else:
    app.quit()
)

app.onKey('\x7f', proc() =
  if addingMode:
    if inputBuffer.len > 0:
      inputBuffer = inputBuffer[0 .. ^2]
  else:
    if todos.len > 0:
      todos.delete(cursor)
      if cursor >= todos.len and cursor > 0:
        cursor = todos.len - 1
)

# アルファベット入力 (追加モード)
for c in 'a'..'z':
  let ch = c
  app.onKey(ch, proc() =
    if addingMode and inputBuffer.len < 40: inputBuffer.add(ch)
  )

for c in 'A'..'Z':
  let ch = c
  app.onKey(ch, proc() =
    if addingMode and inputBuffer.len < 40: inputBuffer.add(ch)
  )

# 数字入力
for c in '0'..'9':
  let ch = c
  app.onKey(ch, proc() =
    if addingMode and inputBuffer.len < 40: inputBuffer.add(ch)
  )

# 記号入力
app.onKey('-', proc() =
  if addingMode and inputBuffer.len < 40: inputBuffer.add('-')
)
app.onKey('_', proc() =
  if addingMode and inputBuffer.len < 40: inputBuffer.add('_')
)
app.onKey('.', proc() =
  if addingMode and inputBuffer.len < 40: inputBuffer.add('.')
)

app.onKey('q', proc() = app.quit())
app.onKey('Q', proc() = app.quit())

# =============================================================================
# アプリケーション実行
# =============================================================================

waitFor app.run(build)
