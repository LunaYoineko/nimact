# Nimact

モダンでシンプルな Nim TUI フレームワーク。コンポーネントベースで宣言的に UI を構築できます。

## 特徴

- **宣言的な API** — コンポーネントを組み立てるだけで UI を構築
- **自動レイアウト** — `vbox`, `hbox`, `center` で座標計算不要
- **自動ドッキング** — header は一番上、footer は一番下に自動配置
- **差分描画** — 変化した部分だけ描画し、60FPS で滑らかな描画
- **TrueColor** — 24bit カラー対応
- **Unicode 対応** — 日本語や絵文字も正しく表示
- **非同期イベントループ** — `async/await` ベース

## インストール

```bash
# 1. プロジェクト作成
mkdir myapp && cd myapp
nimble init

# 2. nimact をインストール
nimble install https://github.com/LunaYoineko/nimact

# 3. .nimble ファイルに依存関係を追記
# myapp.nimble の dependencies セクションに以下を追加:
#   requires "nimact"

# 4. コンパイル・実行
nim c -r src/myapp.nim
```

## クイックスタート

```nim
import std/asyncdispatch
import nimact

var count = 0

let app = newApp()

proc build(): Widget =
  vbox(
    header("My App", fg = colWhite, bg = colBlue, bold = true),
    center(40, 10,
      label("Counter: " & $count, fg = colGreen, bold = true),
      progress(count.float, max = 20.0, fg = colBlue)
    ),
    footer("SPACE: +1 | Q: Quit", fg = colTextMuted, bg = colBgDark)
  )

app.onKey(' ', proc() = inc count)
app.onKey('q', proc() = app.quit())

waitFor app.run(build)
```

header と footer は自動的に画面の上下に配置されます。

## コンポーネント

### label — テキスト表示

```nim
label("Hello, World!")
label("Bold text", fg = colGreen, bold = true)
label("Colored", fg = colRed, bg = colBgCard)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `text` | `string` | 表示テキスト |
| `fg` | `Color` | 前景色（デフォルト: ターミナルのデフォルト） |
| `bg` | `Color` | 背景色 |
| `bold` | `bool` | 太字にするか |

### vbox — 縦並びレイアウト

```nim
vbox(
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

隙間を空ける場合:

```nim
vbox(1,
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

背景色を指定する場合:

```nim
vbox(style(bg = colBgCard),
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

隙間と背景色の両方を指定する場合:

```nim
vbox(1, style(bg = colBgCard),
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `gap` | `int` | 子同士の隙間（行数） |
| `style` | `Style` | コンテナのスタイル（背景色など） |

### hbox — 横並びレイアウト

```nim
hbox(
  label("Left"),
  label("Center"),
  label("Right")
)
```

隙間を空ける場合:

```nim
hbox(2,
  label("A"),
  label("B"),
  label("C")
)
```

背景色を指定する場合:

```nim
hbox(style(bg = colBgCard),
  label("Left"),
  label("Center"),
  label("Right")
)
```

隙間と背景色の両方を指定する場合:

```nim
hbox(2, style(bg = colBgCard),
  label("A"),
  label("B"),
  label("C")
)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `gap` | `int` | 子同士の隙間（列数） |
| `style` | `Style` | コンテナのスタイル（背景色など） |

### center — 中央寄せボックス

指定したサイズの領域を中央に配置し、子ウィジェットをその中で表示します。

```nim
center(40, 10,
  label("This is centered"),
  label("Inside a 40x10 box")
)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `w` | `int` | ボックスの幅 |
| `h` | `int` | ボックスの高さ |

### box — 枠付きパネル

罫線付きのボックスを作成し、中に子ウィジェットを配置します。

```nim
box(30, 8, style(fg = colBlue), bsRounded,
  label("Title", bold = true),
  label("Content")
)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `w` | `int` | ボックスの幅（枠線含む） |
| `h` | `int` | ボックスの高さ（枠線含む） |
| `style` | `Style` | 枠線と内部の装飾スタイル |
| `borderType` | `BorderStyle` | 罫線の種類（デフォルト: `bsRounded`） |

罫線スタイル:

| 定数 | ボーダー |
|---|---|
| `bsSingle` | `┌┐└┘─│` |
| `bsDouble` | `╔╗╚╝═║` |
| `bsRounded` | `╭╮╰╯─│` |
| `bsBold` | `┏┓┗┛━┃` |

### header — ヘッダーバー

画面上部に全幅のバーを表示します。vbox の子として使うと自動的に一番上に配置されます。

```nim
header("My App", fg = colWhite, bg = colBlue, bold = true)
```

### footer — フッターバー

画面下部に全幅のバーを表示します。vbox の子として使うと自動的に一番下に配置されます。

```nim
footer("Q: Quit | SPACE: Action", fg = colTextMuted, bg = colBgDark)
```

### progress — プログレスバー

```nim
progress(0.75)              # 75%（デフォルト max = 1.0）
progress(50.0, max = 100.0) # 50%
progress(5.0, max = 10.0, fg = colCyan)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `value` | `float` | 現在値 |
| `max` | `float` | 最大値（デフォルト: 1.0） |
| `fg` | `Color` | 塗りつぶし部分の色 |

### separator — 区切り線

```nim
separator(fg = colTextMuted)
```

### spacer — 空白スペース

```nim
spacer(2) # 2行分の空白
```

## キーイベント

### 文字キー

```nim
app.onKey(' ', proc() = doSomething())
app.onKey('q', proc() = app.quit())
```

### 特殊キー

```nim
app.onKey(nkUp,     proc() = moveUp())
app.onKey(nkDown,   proc() = moveDown())
app.onKey(nkLeft,   proc() = moveLeft())
app.onKey(nkRight,  proc() = moveRight())
app.onKey(nkEscape, proc() = app.quit())
app.onKey(nkEnter,  proc() = submit())
```

利用可能な `KeyKind`:

| 値 | キー |
|---|---|
| `nkUp` | ↑ |
| `nkDown` | ↓ |
| `nkLeft` | ← |
| `nkRight` | → |
| `nkEscape` | Esc |
| `nkEnter` | Enter |

## カラーパレット

組み込みのカラーコンストラント:

| 定数 | RGB | 用途例 |
|---|---|---|
| `colBlue` | `(97, 175, 239)` | アクセント |
| `colPurple` | `(198, 120, 221)` | タイトル |
| `colGreen` | `(152, 195, 121)` | 成功 |
| `colYellow` | `(229, 192, 123)` | 警告 |
| `colRed` | `(224, 108, 117)` | エラー |
| `colCyan` | `(86, 182, 194)` | 情報 |
| `colText` | `(220, 223, 228)` | メインテキスト |
| `colTextMuted` | `(92, 99, 112)` | 薄いテキスト |
| `colWhite` | `(255, 255, 255)` | 白 |
| `colBgDark` | `(30, 34, 42)` | ダーク背景 |
| `colBgCard` | `(40, 44, 52)` | カード背景 |
| `colBgFocus` | `(50, 56, 66)` | フォーカス背景 |

カスタムカラー:

```nim
let myColor = rgb(255, 128, 0) # オレンジ
label("Custom color", fg = myColor)
```

## スタイル

```nim
style(fg = colGreen, bg = colBgCard, bold = true, dim = true, italic = true, underline = true, reverse = true)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `fg` | `Color` | 前景色 |
| `bg` | `Color` | 背景色 |
| `bold` | `bool` | 太字 |
| `dim` | `bool` | 暗く表示 |
| `italic` | `bool` | 斜体 |
| `underline` | `bool` | 下線 |
| `reverse` | `bool` | 反転 |

## 便利な関数

### drawString — 低レベルテキスト描画

```nim
buf.drawString(10, 5, "Hello", style(fg = colGreen))
```

### drawBox — 低レベルボックス描画

```nim
buf.drawBox(5, 3, 30, 10, style(fg = colBlue), bsRounded)
```

## サンプル

`examples/` ディレクトリに難易度別のサンプルがあります:

| ファイル | 難易度 | 内容 |
|---|---|---|
| `hello.nim` | 初級 | 最小限の「Hello World」 |
| `counter.nim` | 初中級 | カウンター + プログレスバー |
| `dashboard.nim` | 中級 | 複数パネル、カラム配置、ステータス表示 |
| `todo.nim` | 上級 | インタラクティブ TODO リスト |

実行するには:

```bash
nim c -r examples/hello.nim
```

## トラブルシュート

### `cannot open file: nimact`

`.nimble` ファイルに `requires "nimact"` が記述されていない場合に発生します。

`myapp.nimble` を開いて、dependencies セクションに以下を追加してください:

```
requires "nimact"
```

## ライセンス

MIT
