## =============================================================================
## nimact/core/event.nim
## イベントディスパッチシステムを提供するモジュール
##
## このモジュールは以下の機能を提供する:
##   - EventBus: キー入力イベントをハンドラに配信するディスパッチャ
##   - ハンドラ登録: 文字キー・矢印キー・Escape・Enter の各イベントに
##                   複数のコールバック関数を登録できる
##   - dispatch: KeyEvent を受け取り、登録されたハンドラを呼び出す
##
## 使用パターン:
##   1. EventBus を生成
##   2. onChar / onArrow / onEscape / onEnter でハンドラを登録
##   3. メインループで pollKey() → dispatch() を毎フレーム呼ぶ
##   4. dispatch が登録されたハンドラを自動的に呼び出す
##
## 設計思想:
##   - シンプルな observer パターン (pub-sub)
##   - 1つのキーに複数ハンドラを登録可能
##   - ハンドラは proc() (引数なし) で統一
## =============================================================================

import std/tables
import ./input

export input  # inputモジュールの型 (KeyKind, KeyEvent等) を再エクスポート

# =============================================================================
# 型定義
# =============================================================================

type
    ## イベントハンドラの型
    ## 引数なし・戻り値なしのプロシージャ
    EventCallback* = proc()

    ## 矢印キーの種類 (EventBus内部で使用)
    ArrowKey* = enum
        akUp,     ## ↑
        akDown,   ## ↓
        akLeft,   ## ←
        akRight   ## →

    ## イベントディスパッチャ
    ##
    ## 内部的にハンドラを辞書(Table)で管理している:
    ##   - charHandlers: 文字キー → ハンドラ列 (例: 'q' → [proc1, proc2])
    ##   - arrowHandlers: 矢印キー → ハンドラ列
    ##   - escapeHandlers: Escape キーのハンドラ列
    ##   - enterHandlers: Enter キーのハンドラ列
    EventBus* = ref object
        charHandlers*: Table[string, seq[EventCallback]]        ## 文字キーのハンドラ
        anyCharHandlers*: seq[proc(ch: string)]
             ## 全ての文字キー共通ハンドラ
        escapeHandlers*: seq[EventCallback]                    ## Escape のハンドラ
        enterHandlers*: seq[EventCallback]                     ## Enter のハンドラ
        arrowHandlers*: Table[ArrowKey, seq[EventCallback]]   ## 矢印キーのハンドラ

# =============================================================================
# EventBus 生成
# =============================================================================

## 新しいEventBusを生成する
## 初期状態ではハンドラは登録されていない
proc newEventBus*(): EventBus =
    EventBus(
        charHandlers: initTable[string, seq[EventCallback]](),
        arrowHandlers: initTable[ArrowKey, seq[EventCallback]]()
    )

# =============================================================================
# ハンドラ登録関数
# =============================================================================

## 文字キーのハンドラを登録する
## ch: 対象の文字 (例: 'q', ' ')
## handler: キー押下時に呼び出されるコールバック
##
## 同じ文字に複数ハンドラを登録できる (全て呼び出される)
## 使用例: bus.onChar('q', proc() = quit())
proc onChar*(bus: EventBus, ch: string, handler: EventCallback) =
    if ch notin bus.charHandlers:
        bus.charHandlers[ch] = @[]
    bus.charHandlers[ch].add(handler)

proc onAnyChar*(bus: EventBus, handler: proc(ch: string)) =
    bus.anyCharHandlers.add(handler)
    
## Escape キーのハンドラを登録する
proc onEscape*(bus: EventBus, handler: EventCallback) =
    bus.escapeHandlers.add(handler)

## Enter キーのハンドラを登録する
proc onEnter*(bus: EventBus, handler: EventCallback) =
    bus.enterHandlers.add(handler)

## 矢印キーのハンドラを登録する
## arrow: 対象の矢印キー (akUp, akDown, akLeft, akRight)
## handler: キー押下時に呼び出されるコールバック
proc onArrow*(bus: EventBus, arrow: ArrowKey, handler: EventCallback) =
    if arrow notin bus.arrowHandlers:
        bus.arrowHandlers[arrow] = @[]
    bus.arrowHandlers[arrow].add(handler)

# =============================================================================
# イベントディスパッチ
# =============================================================================

## KeyEvent を受け取り、対応するハンドラを全て呼び出す
##
## 処理の流れ:
##   1. key.kind に応じてハンドラテーブルを検索
##   2. 見つかったハンドラを全て順番に呼び出す
##   3. nkChar の場合は key.ch で文字キーのハンドラを検索
##   4. nkNone, nkUnknown の場合は何もしない
##
## 呼び出し順序:
##   - 登録順 (FIFO) で呼び出される
##   - 1フレームで複数キー入力がある場合、pollKey() を複数回呼ぶ必要がある
proc dispatch*(bus: EventBus, key: KeyEvent) =
    case key.kind
    of nkChar:
        if key.ch in bus.charHandlers:
            for h in bus.charHandlers[key.ch]:
                h()
        for h in bus.anyCharHandlers:
            h(key.ch)
    of nkEscape:
        for h in bus.escapeHandlers:
            h()
    of nkEnter:
        for h in bus.enterHandlers:
            h()
    of nkBackspace:
        if "\x7f" in bus.charHandlers:
            for h in bus.charHandlers["\x7f"]:
                h()
    of nkUp:
        if akUp in bus.arrowHandlers:
            for h in bus.arrowHandlers[akUp]:
                h()
    of nkDown:
        if akDown in bus.arrowHandlers:
            for h in bus.arrowHandlers[akDown]:
                h()
    of nkLeft:
        if akLeft in bus.arrowHandlers:
            for h in bus.arrowHandlers[akLeft]:
                h()
    of nkRight:
        if akRight in bus.arrowHandlers:
            for h in bus.arrowHandlers[akRight]:
                h()
    else: discard  # nkNone, nkUnknown は無視
