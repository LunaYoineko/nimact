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
##   2. Register key handlers via onKey()
##   3. Start main loop with run(build)
##   4. Each frame:
##      a. pollKey() reads input
##      b. EventBus.dispatch() invokes handlers
##      c. build() constructs widget tree
##      d. Render widgets to buffer
##      e. Diff-render to terminal
##      f. Sleep 16ms (~60 FPS)
##
## Design:
##   - build() called each frame so external variable changes are reflected automatically
##   - Diff rendering for performance (only changed regions drawn)
##   - async/await for non-blocking event loop
## =============================================================================

import std/asyncdispatch
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
        eventBus: EventBus

# =============================================================================
# App creation and control
# =============================================================================

## Create a new App (running=false, initialized EventBus)
proc newApp*(): App =
    App(running: false, eventBus: newEventBus())

# =============================================================================
# Key event handler registration
# =============================================================================

## Register a handler for a character key
proc onKey*(app: App, ch: char, handler: proc()) =
    app.eventBus.onChar(ch, handler)

## Register a handler for a special key (escape, enter, arrows, etc.)
proc onKey*(app: App, key: KeyKind, handler: proc()) =
    case key
    of nkEscape: app.eventBus.onEscape(handler)
    of nkEnter: app.eventBus.onEnter(handler)
    of nkUp: app.eventBus.onArrow(akUp, handler)
    of nkDown: app.eventBus.onArrow(akDown, handler)
    of nkLeft: app.eventBus.onArrow(akLeft, handler)
    of nkRight: app.eventBus.onArrow(akRight, handler)
    else: discard  # nkChar etc. handled via the char overload above

## Exit the application
proc quit*(app: App) =
    app.running = false

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
##      a. pollKey()
##      b. dispatch event to handlers
##      c. call build() to get widget tree
##      d. render widgets to new buffer
##      e. diff-render to terminal
##      f. sleep 16ms
proc run*(app: App, build: proc(): Widget) {.async.} =
    if not enableRawMode():
        return
    defer: disableRawMode()

    app.running = true

    clearScreen()

    let (initW, initH) = getTerminalSize()
    app.currentBuffer = newBuffer(initW, initH)
    
    while app.running:
        let (w, h) = getTerminalSize()

        # Consume all pending input before rendering
        while true:
            let ev = pollKey()
            if ev.kind == nkNone: break
            app.eventBus.dispatch(ev)

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
