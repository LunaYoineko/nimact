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
    ##   - modKeyHandlers: 修飾キー付き特殊キー → ハンドラ列 (例: Shift+Enter)
    EventBus* = ref object
        charHandlers*: Table[string, seq[EventCallback]]        ## 文字キーのハンドラ
        anyCharHandlers*: seq[proc(ch: string)]
             ## 全ての文字キー共通ハンドラ
        keyObservers*: seq[proc(ev: KeyEvent)]
             ## 全イベント共通のオブザーバ (press/repeat/release の区別などに使用)
        escapeHandlers*: seq[EventCallback]                    ## Escape のハンドラ
        enterHandlers*: seq[EventCallback]                     ## Enter のハンドラ
        arrowHandlers*: Table[ArrowKey, seq[EventCallback]]   ## 矢印キーのハンドラ
        modKeyHandlers*: Table[KeyKind, Table[KeyModifier, seq[EventCallback]]]
             ## 修飾キー付き特殊キーのハンドラ (Shift+Enter, Ctrl+Enter, ...)

# =============================================================================
# EventBus 生成
# =============================================================================

## 新しいEventBusを生成する
## 初期状態ではハンドラは登録されていない
proc newEventBus*(): EventBus =
    EventBus(
        charHandlers: initTable[string, seq[EventCallback]](),
        arrowHandlers: initTable[ArrowKey, seq[EventCallback]](),
        modKeyHandlers: initTable[KeyKind, Table[KeyModifier, seq[EventCallback]]]()
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

## 全ての KeyEvent に反応するオブザーバを登録する
## press / repeat / release のイベント種別も受け取れる
proc onAnyKey*(bus: EventBus, handler: proc(ev: KeyEvent)) =
    bus.keyObservers.add(handler)
    
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

## 修飾キー付き特殊キーのハンドラを登録する
## key: 対象の特殊キー (nkEnter, nkEscape, nkBackspace, 矢印キー等)
## modifier: 修飾キー (kmShift, kmCtrl, kmShiftCtrl)
## handler: キー押下時に呼び出されるコールバック
##
## 修飾キー付きハンドラが登録されると、そのキーは通常のハンドラと
## 区別して処理される (例: Shift+Enter は Enter とは別の動作になる)
proc onModKey*(bus: EventBus, key: KeyKind, modifier: KeyModifier, handler: EventCallback) =
    if key notin bus.modKeyHandlers:
        bus.modKeyHandlers[key] = initTable[KeyModifier, seq[EventCallback]]()
    if modifier notin bus.modKeyHandlers[key]:
        bus.modKeyHandlers[key][modifier] = @[]
    bus.modKeyHandlers[key][modifier].add(handler)

## Shift+<特殊キー> のハンドラを登録する (例: Shift+Enter)
proc onShiftKey*(bus: EventBus, key: KeyKind, handler: EventCallback) =
    bus.onModKey(key, kmShift, handler)

## Ctrl+<特殊キー> のハンドラを登録する (例: Ctrl+Enter)
proc onCtrlKey*(bus: EventBus, key: KeyKind, handler: EventCallback) =
    bus.onModKey(key, kmCtrl, handler)

## Shift+Ctrl+<特殊キー> のハンドラを登録する
proc onShiftCtrlKey*(bus: EventBus, key: KeyKind, handler: EventCallback) =
    bus.onModKey(key, kmShiftCtrl, handler)

## Ctrl+<文字> のハンドラを登録する (例: Ctrl+L, Ctrl+C)
## 文字は対応する制御文字 (0x01..0x1A) に変換されて登録される
proc onCtrlKey*(bus: EventBus, ch: string, handler: EventCallback) =
    if ch.len == 1:
        let c = ch[0]
        if c in 'a' .. 'z':
            bus.onChar($char(ord(c) - ord('a') + 1), handler)
            return
        if c in 'A' .. 'Z':
            bus.onChar($char(ord(c) - ord('A') + 1), handler)
            return
    bus.onChar(ch, handler)

# =============================================================================
# イベントディスパッチ
# =============================================================================

## 修飾キー付き特殊キー (Enter/Escape/Backspace/矢印) をディスパッチする
##
## 修飾キー専用ハンドラが登録されていれば「それだけ」を呼び出す
## (通常のハンドラは呼び出さない: Shift+Enter と Enter を区別するため)。
## 登録がなければ通常のハンドラ列にフォールバックする。
proc dispatchModKey(bus: EventBus, keyKind: KeyKind, modifier: KeyModifier,
                    defaultHandlers: seq[EventCallback]) =
    if modifier != kmNone and keyKind in bus.modKeyHandlers:
        if modifier in bus.modKeyHandlers[keyKind]:
            for h in bus.modKeyHandlers[keyKind][modifier]:
                h()
            return
    for h in defaultHandlers:
        h()

## KeyEvent を受け取り、対応するハンドラを全て呼び出す
##
## 処理の流れ:
##   1. key.kind に応じてハンドラテーブルを検索
##   2. 見つかったハンドラを全て順番に呼び出す
##   3. nkChar の場合は key.ch で文字キーのハンドラを検索
##   4. 修飾キー付きの場合は修飾キー専用ハンドラを優先する
##   5. nkNone, nkUnknown の場合は何もしない
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
        bus.dispatchModKey(nkEscape, key.modifier, bus.escapeHandlers)
    of nkEnter:
        bus.dispatchModKey(nkEnter, key.modifier, bus.enterHandlers)
    of nkBackspace:
        bus.dispatchModKey(nkBackspace, key.modifier,
                           bus.charHandlers.getOrDefault("\x7f", newSeq[EventCallback]()))
    of nkUp:
        bus.dispatchModKey(nkUp, key.modifier,
                           bus.arrowHandlers.getOrDefault(akUp, newSeq[EventCallback]()))
    of nkDown:
        bus.dispatchModKey(nkDown, key.modifier,
                           bus.arrowHandlers.getOrDefault(akDown, newSeq[EventCallback]()))
    of nkLeft:
        bus.dispatchModKey(nkLeft, key.modifier,
                           bus.arrowHandlers.getOrDefault(akLeft, newSeq[EventCallback]()))
    of nkRight:
        bus.dispatchModKey(nkRight, key.modifier,
                           bus.arrowHandlers.getOrDefault(akRight, newSeq[EventCallback]()))
    else: discard  # nkNone, nkUnknown は無視

    # 全イベント共通オブザーバ (trackKey の press/repeat/release 更新など)
    for obs in bus.keyObservers:
        obs(key)
