## =============================================================================
## nimact/app.nim
## Main application module providing:
##   - App: Core state object
##   - newApp(): App constructor
##   - onKey(): Key event handler registration (char / special keys)
##   - quit(): Exit the application
##   - run(): Async main loop
##
## Application flow:
##   1. Create App via newApp()
##   2. Register key handlers via onKey() / onUpdate() / trackKey()
##   3. Start main loop with run(build)
##   4. Each frame (~60 FPS, time-driven):
##      a. pollKey() drains pending input non-blockingly
##      b. EventBus.dispatch() invokes handlers
##      c. onUpdate() handlers run (game logic)
##      d. build() constructs widget tree
##      e. Render widgets to buffer
##      f. Diff-render to terminal
##      g. Sleep 16ms (~60 FPS)
##
## The loop is time-driven, not input-driven: pollKey() returns immediately
## when no input is pending (select with zero timeout), so rendering and
## onUpdate() run at a constant frame rate even while idle or while a key is
## being held down.
##
## Design:
##   - build() called each frame so external variable changes are reflected automatically
##   - Diff rendering for performance (only changed regions drawn)
##   - async/await for non-blocking event loop
## =============================================================================

import std/asyncdispatch
import std/tables
import std/times
import ./core/term
import ./core/input
import ./core/buffer
import ./core/event
import ./components/widget

export widget, buffer, event  # re-export for library consumers

# =============================================================================
# App type definition
# =============================================================================

type
    ## Application state object
    App* = ref object
        running: bool
        currentBuffer: Buffer
        eventBus*: EventBus
        updateHandlers: seq[proc()]          ## called once per frame before build()
        deltaHandlers: seq[proc(dt: float)]  ## per-frame handlers receiving dt (seconds)
        deltaTime*: float                    ## seconds since the last frame
        heldState: Table[string, bool]       ## trackKey(): ch -> currently held?
        heldSince: Table[string, float]      ## trackKey(): ch -> last press/repeat time
        repeatSeen: Table[string, bool]      ## trackKey(): ch -> a repeat was observed
        kittySeen*: bool                     ## true once a keRepeat/keRelease is dispatched
        repeatWindow: float                  ## release timeout after the last repeat (sec)
        initialHoldWindow: float             ## release timeout before the first repeat (sec)
        safetyTimeout: float                 ## hard limit for kitty keys (lost-release fallback)

# =============================================================================
# App creation and control
# =============================================================================

## Create a new App (running=false, initialized EventBus)
proc newApp*(): App =
    App(running: false, eventBus: newEventBus(),
        updateHandlers: @[], deltaHandlers: @[],
        heldState: initTable[string, bool](),
        heldSince: initTable[string, float](),
        repeatSeen: initTable[string, bool](),
        kittySeen: false,
        repeatWindow: 0.25, initialHoldWindow: 0.5, safetyTimeout: 2.0)

# =============================================================================
# Key event handler registration
# =============================================================================

## Register a handler for a character key
proc onKey*(app: App, ch: string, handler: proc()) =
    app.eventBus.onChar(ch, handler)

proc onKey*(app: App, ch: char, handler: proc()) =
    app.eventBus.onChar($ch, handler)
    
proc onAnyChar*(app: App, handler: proc(ch: string)) =
    app.eventBus.onAnyChar(handler)
    
proc onAnyChar*(app: App, handler: proc(ch: char)) =
    app.eventBus.onAnyChar(proc(s: string) =
        if s.len > 0:
            handler(s[0])
    )

## Register a handler for a special key (escape, enter, arrows, backspace, etc.)
proc onKey*(app: App, key: KeyKind, handler: proc()) =
        case key
        of nkEscape: app.eventBus.onEscape(handler)
        of nkEnter: app.eventBus.onEnter(handler)
        of nkUp: app.eventBus.onArrow(akUp, handler)
        of nkDown: app.eventBus.onArrow(akDown, handler)
        of nkLeft: app.eventBus.onArrow(akLeft, handler)
        of nkRight: app.eventBus.onArrow(akRight, handler)
        of nkBackspace: app.eventBus.onChar("\x7f", handler)
        else: discard  # nkChar etc. handled via the char overload above

## Register a handler for a modified special key (Shift+Enter, Ctrl+Enter, ...)
proc onModKey*(app: App, key: KeyKind, modifier: KeyModifier, handler: proc()) =
    app.eventBus.onModKey(key, modifier, handler)

## Register a handler for Shift+<special key> (e.g. Shift+Enter)
proc onShiftKey*(app: App, key: KeyKind, handler: proc()) =
    app.eventBus.onModKey(key, kmShift, handler)

## Register a handler for Ctrl+<special key> (e.g. Ctrl+Enter)
proc onCtrlKey*(app: App, key: KeyKind, handler: proc()) =
    app.eventBus.onModKey(key, kmCtrl, handler)

## Register a handler for Shift+Ctrl+<special key>
proc onShiftCtrlKey*(app: App, key: KeyKind, handler: proc()) =
    app.eventBus.onModKey(key, kmShiftCtrl, handler)

## Register a handler for Ctrl+<letter> (e.g. Ctrl+L, Ctrl+C)
## The letter is converted to the corresponding control character.
proc onCtrlKey*(app: App, ch: string, handler: proc()) =
    app.eventBus.onCtrlKey(ch, handler)

## Exit the application
proc quit*(app: App) =
    app.running = false

# =============================================================================
# Per-frame update hook
# =============================================================================

## Register a handler that runs once per frame, right before build().
## Use this for game logic (movement, physics, timers) so it is kept
## separate from rendering.
proc onUpdate*(app: App, handler: proc()) =
    app.updateHandlers.add(handler)

## Register a per-frame handler that receives the elapsed time `dt` in
## seconds since the last frame. Use this for frame-rate-independent
## movement (game-engine style): `if app.isHeld('w'): move(speed * dt)`.
proc onUpdate*(app: App, handler: proc(dt: float)) =
    app.deltaHandlers.add(handler)

# =============================================================================
# Key hold detection
# =============================================================================

## Start tracking a key for hold detection (game-engine style).
##
## A key is considered "held" from the moment it is pressed until it is
## released, so isHeld() stays true (and movement keeps running every frame)
## regardless of the terminal's key-repeat timing. Two mechanisms end a hold:
##
##   1. Kitty keyboard protocol (enabled by default): the terminal reports an
##      explicit release event, which ends the hold immediately. The framework
##      auto-detects kitty support once a keRepeat or keRelease event arrives
##      and switches to release-only mode (no premature timeout release).
##   2. Fallback (terminals without kitty): once key events stop arriving the
##      key is treated as released after a timeout. The timeout is `repeatDelay`
##      (default 0.25s) once at least one repeat has been observed, and
##      `initialHoldWindow` (default 0.5s) before the first repeat, so the gap
##      between press and the first repeat (typematic delay) never causes a
##      stutter in the middle of a hold. The wider repeatDelay tolerates SSH
##      jitter at the cost of slightly more release drift.
##
## Note: enabling this registers an internal event observer for `ch`.
proc trackKey*(app: App, ch: string, repeatDelay: float = 0.25) =
    app.repeatWindow = max(app.repeatWindow, repeatDelay)
    if ch notin app.heldState:
        app.heldState[ch] = false
        app.heldSince[ch] = 0.0
        app.repeatSeen[ch] = false
        app.eventBus.onAnyKey(proc(ev: KeyEvent) =
            if ev.kind == nkChar and ev.ch == ch:
                case ev.eventType
                of keRelease:
                    app.heldState[ch] = false
                of keRepeat:
                    app.repeatSeen[ch] = true
                    app.kittySeen = true
                    app.heldState[ch] = true
                    app.heldSince[ch] = epochTime()
                of kePress:
                    if app.heldState[ch]:
                        app.repeatSeen[ch] = true
                    app.heldState[ch] = true
                    app.heldSince[ch] = epochTime()
                else: discard
        )

proc trackKey*(app: App, ch: char, repeatDelay: float = 0.15) =
    app.trackKey($ch, repeatDelay)

## Start tracking a special key (KeyKind) for hold detection.
## Works for arrows, backspace, etc. — keys that are not nkChar.
proc trackKeyKind*(app: App, key: KeyKind, repeatDelay: float = 0.25) =
    let keyStr = "kind:" & $key
    app.repeatWindow = max(app.repeatWindow, repeatDelay)
    if keyStr notin app.heldState:
        app.heldState[keyStr] = false
        app.heldSince[keyStr] = 0.0
        app.repeatSeen[keyStr] = false
        app.eventBus.onAnyKey(proc(ev: KeyEvent) =
            if ev.kind == key:
                case ev.eventType
                of keRelease:
                    app.heldState[keyStr] = false
                of keRepeat:
                    app.repeatSeen[keyStr] = true
                    app.kittySeen = true
                    app.heldState[keyStr] = true
                    app.heldSince[keyStr] = epochTime()
                of kePress:
                    if app.heldState[keyStr]:
                        app.repeatSeen[keyStr] = true
                    app.heldState[keyStr] = true
                    app.heldSince[keyStr] = epochTime()
                else: discard
        )

## Whether `ch` is currently held (pressed and not yet released).
## Only works for keys registered with trackKey().
proc isHeld*(app: App, ch: string): bool =
    app.heldState.getOrDefault(ch, false)

proc isHeld*(app: App, ch: char): bool =
    app.isHeld($ch)

## Whether a special key (KeyKind) is currently held.
## Only works for keys registered with trackKeyKind().
proc isHeldKind*(app: App, key: KeyKind): bool =
    app.heldState.getOrDefault("kind:" & $key, false)

## Release keys whose events have stopped arriving.
## Called once per frame by run(); exported so it can be driven manually in tests.
##
## Two modes:
##   - kittySeen: the terminal reports release events. The key is only released
##     by a keRelease event (already handled in the observer). This fallback
##     acts as a safety net: if a release event is somehow lost, the key is
##     released after `safetyTimeout` (default 2s).
##   - not kittySeen: plain-byte terminal. The key is released after
##     `repeatWindow` (0.25s) once a repeat has been seen, or
##     `initialHoldWindow` (0.5s) before the first repeat.
proc checkKeyReleases*(app: App) =
    for ch, held in app.heldState.mpairs:
        if not held: continue
        if app.kittySeen:
            if epochTime() - app.heldSince[ch] > app.safetyTimeout:
                app.heldState[ch] = false
        else:
            let timeout = if app.repeatSeen[ch]: app.repeatWindow else: app.initialHoldWindow
            if epochTime() - app.heldSince[ch] > timeout:
                app.heldState[ch] = false

# =============================================================================
# Main loop
# =============================================================================

## Start the async main loop
##
## build: Called each frame; returns the widget tree to render.
## External variable changes are reflected automatically.
##
## Steps:
##   1. Enable raw mode (restored on exit via defer)
##   2. Get terminal size and init buffer
##   3. Clear screen
##   4. Loop while running:
##      a. compute deltaTime since the last frame
##      b. pollKey() drains pending input non-blockingly
##      c. dispatch event to handlers
##      d. checkKeyReleases() releases timed-out held keys
##      e. call onUpdate() handlers (game logic, with dt)
##      f. call build() to get widget tree
##      g. render widgets to new buffer, diff-render to terminal
##      h. sleep 16ms
proc run*(app: App, build: proc(): Widget) {.async.} =
    if not enableRawMode():
        return
    defer: disableRawMode()

    app.running = true

    clearScreen()

    let (initW, initH) = getTerminalSize()
    app.currentBuffer = newBuffer(initW, initH)
    var lastFrameTime = epochTime()

    while app.running:
        let now = epochTime()
        app.deltaTime = now - lastFrameTime
        lastFrameTime = now

        let (w, h) = getTerminalSize()

        # Consume all pending input before rendering
        while true:
            let ev = pollKey()
            if ev.kind == nkNone: break
            app.eventBus.dispatch(ev)

        # Release keys whose events stopped (non-kitty terminal fallback)
        app.checkKeyReleases()

        # Run per-frame update handlers (game logic) before rendering
        for h in app.updateHandlers:
            h()
        for h in app.deltaHandlers:
            h(app.deltaTime)

        let rootWidget = build()
        let nextBuffer = newBuffer(w, h)

        var targetContainer: Widget = nil
        var dockedHeader: Widget = nil
        var dockedFooter: Widget = nil
        
        # Find root container (vbox/hbox)
        if rootWidget.kind == wkVBox or rootWidget.kind == wkHBox:
            targetContainer = rootWidget
        elif rootWidget.kind == wkCenter:
            for child in rootWidget.centerChildren:
                if child.kind == wkVBox or child.kind == wkHBox:
                    targetContainer = child
                    break
        
        if targetContainer != nil:
            var contentChildren: seq[Widget] = @[]
            for child in targetContainer.children:
                case child.kind
                of wkHeader: dockedHeader = child
                of wkFooter: dockedFooter = child
                else: contentChildren.add(child)
                
            let headerH = if dockedHeader != nil: 1 else: 0
            let footerH = if dockedFooter != nil: 1 else: 0
                
            let contentY = headerH
            let contentH = max(0, h - headerH - footerH)
            
            if contentChildren.len > 0:
                if targetContainer.kind == wkVBox:
                    let contentContainer = Widget(
                            kind: wkVBox,
                            children: contentChildren,
                            gap: targetContainer.gap,
                            vhboxStyle: targetContainer.vhboxStyle
                    )
                    contentContainer.render(nextBuffer, 0, contentY, w, contentH)
                else:
                    let contentContainer = Widget(
                            kind: wkHBox,
                            children: contentChildren,
                            gap: targetContainer.gap,
                            vhboxStyle: targetContainer.vhboxStyle
                    )
                    contentContainer.render(nextBuffer, 0, contentY, w, contentH)
                
            if dockedHeader != nil:
                dockedHeader.render(nextBuffer, 0, 0, w, 1)
                
            if dockedFooter != nil:
                dockedFooter.render(nextBuffer, 0, h - 1, w, 1)
                
        else:
            rootWidget.render(nextBuffer, 0, 0, w, h)
                
        # Diff render and swap buffers
        if app.currentBuffer == nil or app.currentBuffer.width != w or app.currentBuffer.height != h:
            app.currentBuffer = newBuffer(w, h)
                
        renderDiff(app.currentBuffer, nextBuffer)
        app.currentBuffer = nextBuffer
            
            
        await sleepAsync(16)
