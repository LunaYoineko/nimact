## =============================================================================
## examples/dashboard.nim
## nimact の中級サンプル: ダッシュボード
##
## このサンプルは以下の機能をデモしている:
##   - hbox による左右カラム配置
##   - 複数の vbox ネスト
##   - 色分けされたステータス表示
##   - 動的に変化するカウンタ
##   - progress バーの活用
##
## 操作方法:
##   SPACE キー: カウンターを加算
##   R キー:     カウンターをリセット
##   Q キー:     アプリケーションを終了
## =============================================================================

import std/asyncdispatch
import ../src/nimact

# =============================================================================
# アプリケーションの状態
# =============================================================================

var
  reqCount = 0       ## リクエスト数
  errCount = 0       ## エラー数
  activeConns = 0    ## アクティブ接続数
  cpuUsage = 35.0    ## CPU使用率 (%)
  memUsage = 62.0    ## メモリ使用率 (%)

let app = newApp()

# =============================================================================
# ウィジェットツリーの構築
# =============================================================================

proc build(): Widget =
  vbox(
    header(" Dashboard Like App v0.1.0 ", fg = colWhite, bg = colBlue, bold = true),

    hbox(2,
      # --- 左カラム: 統計情報 ---
      vbox(1,
        label(" [ リクエスト ] ", fg = colPurple, bold = true),
        label("トータル:  " & $reqCount, fg = colText),
        label("エラー: " & $errCount, fg = colRed),
        label("アクティブ: " & $activeConns, fg = colCyan),
        spacer(1),
        label(" [ CPU ] ", fg = colPurple, bold = true),
        progress(cpuUsage, max = 100.0, fg = colGreen),
        label(" " & $cpuUsage.int & "%", fg = colTextMuted),
        spacer(1),
        label(" [ Memory ] ", fg = colPurple, bold = true),
        progress(memUsage, max = 100.0, fg = colYellow),
        label(" " & $memUsage.int & "%", fg = colTextMuted)
      ),

      # --- 右カラム: ステータス ---
      vbox(3,
        label(" [ ステータス ] ", fg = colPurple, bold = true),
        label("  サーバー:   ", fg = colText),
        label("    ", fg = colGreen, bold = true),
        label(" 実行中", fg = colGreen),
        label("  Uptime:   ", fg = colText),
        label("    ", fg = colCyan, bold = true),
        label(" 2h 15m", fg = colCyan),
        label("  バージョン:  ", fg = colText),
        label("    ", fg = colYellow, bold = true),
        label(" 0.1.0", fg = colYellow),
        spacer(1),
        label(" [ Log ] ", fg = colPurple, bold = true),
        label("  最後のリクエスト: OK", fg = colTextMuted),
        label("  次のチェック:   5s", fg = colTextMuted),
      ),
    ),

    footer(" SPACE: +request | R: Reset | Q: Quit ", fg = colTextMuted, bg = colBgDark)
  )

# =============================================================================
# キーイベントハンドラの登録
# =============================================================================

app.onKey(' ', proc() =
  inc reqCount
  activeConns = min(activeConns + 1, 100)
  cpuUsage = min(cpuUsage + 2.5, 100.0)
  memUsage = min(memUsage + 1.0, 100.0)
  if reqCount mod 5 == 0:
    inc errCount
)

app.onKey('r', proc() =
  reqCount = 0
  errCount = 0
  activeConns = 0
  cpuUsage = 35.0
  memUsage = 62.0
)

app.onKey('q', proc() = app.quit())
app.onKey('Q', proc() = app.quit())

# =============================================================================
# アプリケーション実行
# =============================================================================

waitFor app.run(build)
