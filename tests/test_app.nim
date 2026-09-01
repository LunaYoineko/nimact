import std/[unittest, os]
import nimact

suite "app key hold detection":

  test "isHeld returns false for untracked key":
    let app = newApp()
    check not app.isHeld('w')
    check not app.isHeld("w")

  test "press holds the key until a release event":
    let app = newApp()
    app.trackKey('w')
    check not app.isHeld('w')

    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: kePress))
    check app.isHeld('w')

    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: keRelease))
    check not app.isHeld('w')

  test "kitty repeats keep key held without premature release":
    let app = newApp()
    app.trackKey('w')
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: kePress))
    check app.isHeld('w')

    # longer than repeatWindow (0.25) but a kitty repeat arrives -> still held
    sleep(400)
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: keRepeat))
    check app.isHeld('w')
    check app.kittySeen  # kitty mode detected after keRepeat

    # safety timeout is 2s, so 0.5s wait should still be held
    sleep(500)
    app.checkKeyReleases()
    check app.isHeld('w')

  test "kitty release event ends hold immediately":
    let app = newApp()
    app.trackKey('w')
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: kePress))
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: keRepeat))
    check app.isHeld('w')
    check app.kittySeen

    # release event -> held false, even though safety timeout hasn't expired
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: keRelease))
    check not app.isHeld('w')

  test "non-kitty fallback releases after repeatWindow":
    let app = newApp()
    app.trackKey('w', repeatDelay = 0.2)
    # plain bytes: kePress (no keRepeat/keRelease) -> kittySeen stays false
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: kePress))
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: kePress))  # 2nd press = repeatSeen
    sleep(300)  # > 0.2s repeatWindow
    app.checkKeyReleases()
    check not app.isHeld('w')
    check not app.kittySeen

  test "key stays held through the typematic delay (initial window)":
    let app = newApp()
    app.trackKey('w')
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w", eventType: kePress))

    # well past repeatWindow (0.25) but no repeat yet; the initial hold window
    # (0.5s) must bridge the gap until the first repeat arrives
    sleep(350)
    app.checkKeyReleases()
    check app.isHeld('w')

  test "plain-byte repeats are recognized as repeats":
    let app = newApp()
    app.trackKey('w', repeatDelay = 0.15)
    # plain bytes arrive as kePress (terminals without kitty protocol)
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w"))
    check app.isHeld('w')
    # a second press while already held is treated as a repeat
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "w"))
    sleep(250)
    app.checkKeyReleases()
    check not app.isHeld('w')

  test "string overload works for tracking":
    let app = newApp()
    app.trackKey("d", repeatDelay = 0.2)
    app.eventBus.dispatch(KeyEvent(kind: nkChar, ch: "d"))
    check app.isHeld("d")
    check app.isHeld('d')

suite "app update hook":

  test "onUpdate registers handlers without error":
    let app = newApp()
    var frames = 0
    app.onUpdate(proc() = inc frames)
    app.onUpdate(proc() = discard)
    check true

  test "onUpdate with dt registers without error":
    let app = newApp()
    var sum = 0.0
    app.onUpdate(proc(dt: float) = sum += dt)
    check true
