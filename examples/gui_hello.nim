## =============================================================================
## examples/gui_hello.nim
## GUI フレームワークのデモアプリケーション
## =============================================================================

import nimactgui

proc main() =
  var counter = 0

  let app = newApp("Nimact GUI Demo", 800, 600)

  let handler = newGuiEventHandler()
  handler.onKeyPress = proc(keySym: culong, keyStr: string): bool =
    if keySym == XK_Escape:
      app.running = false
      return true
    return false

  let redBtnStyle = buttonStyle(bg = colRed, radius = 8)
  let greenBtnStyle = buttonStyle(bg = colGreen, radius = 8)
  let purpleBtnStyle = buttonStyle(bg = colPurple, radius = 8)

  proc incCounter() =
    if counter < 10: counter += 1
    app.needsRedraw = true

  proc decCounter() =
    if counter > 0: counter -= 1
    app.needsRedraw = true

  proc resetCounter() =
    counter = 0
    app.needsRedraw = true

  let buildProc = proc(): Widget =
    scaffold(
      column(
        center(
          column(
            text("Nimact GUI Framework", textStyle(size = 28, color = colBlue, weight = fwBold)),
            text("Flutter-like declarative UI for Nim", textStyle(size = 14, color = colTextMuted))
          ),
          width = -1,
          height = 120
        ),
        expanded(
          padding(
            column(
              card(
                column(
                  text("Counter", textStyle(size = 20, color = colText, weight = fwBold)),
                  text("Count: " & $counter, textStyle(size = 16, color = colCyan)),
                  progressBar(counter.float / 10.0, color = colGreen, trackColor = colBgFocus),
                  row(12,
                    button("  -  ", decCounter, redBtnStyle),
                    button("  +  ", incCounter, greenBtnStyle),
                    button("Reset", resetCounter, purpleBtnStyle)
                  )
                ),
                padding = insets(24),
                margin = insets(4),
                radius = 12,
                color = colBgCard
              ),
              row(16,
                card(
                  column(
                    text("Features", textStyle(size = 16, color = colYellow, weight = fwBold)),
                    text("- Declarative widgets", textStyle(size = 13, color = colText)),
                    text("- X11 rendering", textStyle(size = 13, color = colText)),
                    text("- FreeType text", textStyle(size = 13, color = colText)),
                    text("- Zero dependencies", textStyle(size = 13, color = colText))
                  ),
                  padding = insets(20),
                  radius = 12,
                  color = colBgCard
                ),
                expanded(
                  card(
                    column(
                      text("Layout", textStyle(size = 16, color = colCyan, weight = fwBold)),
                      text("Row / Column / Stack", textStyle(size = 13, color = colText)),
                      text("Center / Expanded", textStyle(size = 13, color = colText)),
                      text("Padding / Align", textStyle(size = 13, color = colText)),
                      text("Card / Container", textStyle(size = 13, color = colText))
                    ),
                    padding = insets(20),
                    radius = 12,
                    color = colBgCard
                  )
                )
              ),
              center(
                text("Press Escape to quit | " & $counter & " clicks", textStyle(size = 12, color = colTextMuted)),
                height = 40
              )
            ),
            insets(0, 24)
          )
        )
      ),
      AppBarConfig(
        title: "Nimact GUI Demo",
        bgColor: rgb(30, 34, 42),
        fgColor: colWhite,
        height: 48
      )
    )

  app.run(buildProc, handler)

main()
