import AppKit

/// Owns one transparent, click-through overlay window per screen, moves the
/// pointer to follow the cursor, and hosts the ink.
final class OverlayController {
    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class Screenlet {
        let window: OverlayWindow
        let host: NSView
        let spotlight = SpotlightLayer()
        let ink = InkLayer()
        let stamps = StampLayer()
        let snap = SnapLayer()
        let pointer = PointerLayer()

        init(screen: NSScreen) {
            // Global coordinates, and deliberately no `screen:` argument: that
            // initializer reads the rect as relative to the screen's origin,
            // which doubled the offset and put every non-primary display's
            // overlay off-screen. setFrame pins it to the screen exactly.
            window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            // Above everything, including full-screen apps and the menu bar.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

            host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            host.wantsLayer = true
            host.layer?.masksToBounds = false
            window.contentView = host

            spotlight.frame = host.bounds
            ink.frame = host.bounds
            stamps.frame = host.bounds
            stamps.scale = screen.backingScaleFactor
            pointer.frame = host.bounds
            snap.frame = host.bounds
            snap.configure(scale: screen.backingScaleFactor)
            pointer.applyPrefs(screenSize: screen.frame.size)
            host.layer?.addSublayer(spotlight)
            host.layer?.addSublayer(ink)
            host.layer?.addSublayer(stamps)
            host.layer?.addSublayer(snap)
            host.layer?.addSublayer(pointer)
            pointer.isHidden = true
        }
    }

    private(set) var isActive = false
    /// Starts from, and is saved back to, Settings (so ⌃⌥L sticks across launches).
    var style: PointerStyle = Prefs.pointerStyle {
        didSet {
            screenlets.forEach { $0.pointer.pointerStyle = style; $0.snap.showsRing = style != .reticle }
            if Prefs.pointerStyle != style { Prefs.pointerStyle = style }
        }
    }
    var spotlight = false {
        didSet {
            screenlets.forEach { $0.spotlight.isHidden = !spotlight; $0.spotlight.update(cursor: nil) }
            if isActive { tick() }
        }
    }

    var snap = Prefs.snapToElements {
        didSet {
            if !snap { target = nil; screenlets.forEach { $0.snap.hide() } }
            if Prefs.snapToElements != snap { Prefs.snapToElements = snap }
        }
    }

    private var screenlets: [Screenlet] = []
    /// Where the hand is drawn (global Cocoa coords); eases toward the goal.
    private var shown: NSPoint?
    private var target: AXProbe.Target?
    private var probing = false
    private var tickCount = 0
    private let probeQueue = DispatchQueue(label: "Fingertip.AXProbe", qos: .userInteractive)
    private var frameTimer: Timer?
    private var activeScreenlet: Screenlet?

    /// Step stamps: each tap (not a drag) drops the next numbered badge.
    var stepStamps = false
    private var stampCount = 0
    /// Strokes and stamps in the order they were made, for undo.
    private var history: [(layer: CALayer, screen: Screenlet, isStamp: Bool)] = []
    /// The cursor position tick() used last.
    private var lastCursor: NSPoint = .zero
    /// Where the current press started: hand point, screen, snapped frame
    /// (local coords) and cursor, to tell a tap from a drag on release.
    private var pressOrigin: (global: NSPoint, screen: Screenlet, lock: CGRect?, cursor: NSPoint)?
    private var pressMoved: Bool {
        guard let o = pressOrigin else { return false }
        return hypot(lastCursor.x - o.cursor.x, lastCursor.y - o.cursor.y) >= Prefs.tapSlop
    }
    private var screenObserver: NSObjectProtocol?
    private var prefsObserver: NSObjectProtocol?
    private var drawing = false

    init() {
        rebuildScreens()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildScreens() }
        prefsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyPrefs() }
    }

    /// Re-reads Settings into live state and into values baked into layers.
    /// Cheap enough to run on every slider tick.
    func applyPrefs() {
        if style != Prefs.pointerStyle { style = Prefs.pointerStyle }
        if snap != Prefs.snapToElements { snap = Prefs.snapToElements }
        for s in screenlets {
            s.spotlight.applyPrefs()
            s.snap.applyPrefs()
            s.pointer.applyPrefs(screenSize: s.window.frame.size)
        }
        if isActive { Prefs.hideSystemCursor ? CursorHider.hide() : CursorHider.show() }
    }

    // MARK: Activation

    func activate() {
        guard !isActive else { return }
        isActive = true
        screenlets.forEach { $0.window.orderFrontRegardless() }
        if Prefs.hideSystemCursor { CursorHider.hide() }
        tick()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        frameTimer?.invalidate()
        frameTimer = nil
        CursorHider.show()
        drawing = false
        screenlets.forEach {
            $0.ink.end()
            $0.pointer.release()
            $0.pointer.isHidden = true
            $0.window.orderOut(nil)
        }
        activeScreenlet = nil
        shown = nil
        target = nil
        pressOrigin = nil
        screenlets.forEach { $0.snap.hide() }
    }

    /// Clears ink and step stamps, and restarts stamp numbering.
    func clearInk() {
        screenlets.forEach { $0.ink.clear(); $0.stamps.clear() }
        stampCount = 0
        history.removeAll()
    }

    /// Removes the most recent stroke or stamp still on screen (ink that
    /// already faded is skipped). Beeps when there is nothing left.
    func undo() {
        while let last = history.popLast() {
            guard last.layer.superlayer != nil, last.layer.opacity > 0 else { continue }
            if last.isStamp {
                last.screen.stamps.remove(last.layer)
                stampCount = max(0, stampCount - 1)  // LIFO, so this was the highest number
            } else {
                last.screen.ink.remove(last.layer)
            }
            return
        }
        NSSound.beep()
    }

    private func remember(_ layer: CALayer, on s: Screenlet, isStamp: Bool) {
        history.removeAll { $0.layer.superlayer == nil }  // drop faded and removed marks
        history.append((layer, s, isStamp))
    }

    private func dropStamp(_ o: (global: NSPoint, screen: Screenlet, lock: CGRect?, cursor: NSPoint)) {
        stampCount += 1
        let c: CGPoint
        if let lock = o.lock {
            c = CGPoint(x: lock.minX, y: lock.maxY)  // snapped element's top-left corner
        } else {
            let p = local(o.global, in: o.screen)
            c = CGPoint(x: p.x + 18, y: p.y + 18)   // up and right of the fingertip
        }
        remember(o.screen.stamps.add(number: stampCount, at: c), on: o.screen, isStamp: true)
    }

    // MARK: Input from the event tap (CG coordinates, top-left origin)

    func press(atCG cgPoint: CGPoint) {
        guard isActive else { return }
        // Tap where the hand is; if it is mid-glide between displays, where the cursor is.
        let cursor = cocoaPoint(fromCG: cgPoint)
        var global = shown ?? cursor
        if screenlet(containingGlobal: global) == nil { global = cursor }
        beginPress(global: global)
    }

    private func beginPress(global: NSPoint) {
        guard let s = screenlet(containingGlobal: global) else { return }
        let p = local(global, in: s)
        if s !== activeScreenlet {
            activeScreenlet?.pointer.isHidden = true
            activeScreenlet = s
            s.pointer.isHidden = false
        }
        s.pointer.press()
        TapSound.play()
        // Click-through: the app gets the click and the drag, so show a
        // ripple instead of starting ink.
        if Prefs.clickThrough {
            ClickRipple.add(to: s.stamps, at: p)
        } else {
            // Shift-drag draws an arrow, Option-drag highlights, a plain drag is ink.
            let mods = NSEvent.modifierFlags
            let kind: InkLayer.Kind = mods.contains(.shift) ? .arrow : mods.contains(.option) ? .highlighter : .pen
            remember(s.ink.begin(at: p, width: Prefs.inkWidth, kind: kind), on: s, isStamp: false)
        }
        drawing = true
        pressOrigin = (global, s, s.pointer.lockRect, lastCursor)
    }

    private func endPress() {
        guard drawing else { return }
        if stepStamps, let o = pressOrigin, !pressMoved { dropStamp(o) }
        pressOrigin = nil
        screenlets.forEach { $0.pointer.release(); $0.ink.end() }
        drawing = false
    }

    func pressure(_ p: CGFloat) {
        guard isActive, drawing, let s = activeScreenlet else { return }
        s.ink.setPressure(p)
    }

    func release(atCG cgPoint: CGPoint) {
        guard isActive else { return }
        endPress()
    }

    // MARK: Per-frame

    private func tick() {
        let cursor = NSEvent.mouseLocation
        lastCursor = cursor
        guard let s = screenlet(containingGlobal: cursor) ?? activeScreenlet else { return }
        if s !== activeScreenlet {
            activeScreenlet?.pointer.isHidden = true
            activeScreenlet?.spotlight.update(cursor: nil)
            activeScreenlet?.snap.hide()
            activeScreenlet = s
            s.pointer.isHidden = false
        }

        tickCount += 1
        if snap, tickCount % 6 == 0 { probe(cursorCG: cgPoint(fromCocoa: cursor)) }

        // Snap goal: element center while the cursor is inside it. Released
        // once a press turns into a drag, or a stroke inside a large element
        // could never leave its centre; a plain tap stays on the centre.
        var goal = cursor
        if snap, !(drawing && pressMoved), let t = target {
            let f = cocoaRect(fromCG: t.frameCG)
            if f.contains(cursor) {
                goal = NSPoint(x: f.midX, y: f.midY)
                s.snap.show(frame: localRect(f, in: s), label: t.label)
                s.pointer.lockRect = localRect(f, in: s)
            } else {
                s.snap.hide()
                s.pointer.lockRect = nil
            }
        } else {
            s.snap.hide()
            s.pointer.lockRect = nil
        }

        let prev = shown ?? goal
        let e = Prefs.handEase
        let next = NSPoint(x: prev.x + (goal.x - prev.x) * e, y: prev.y + (goal.y - prev.y) * e)
        shown = next

        let p = local(next, in: s)
        s.pointer.update(cursor: p, in: s.host.bounds, animated: true)
        if spotlight { s.spotlight.update(cursor: p) }
        if drawing { s.ink.extend(to: p) }
    }

    /// AX hit tests can block on a busy app, so they run off the main thread
    /// and only one is in flight at a time.
    private func probe(cursorCG: CGPoint) {
        guard !probing else { return }
        probing = true
        probeQueue.async { [weak self] in
            let t = AXProbe.target(atCG: cursorCG)
            DispatchQueue.main.async {
                self?.target = t
                self?.probing = false
            }
        }
    }

    // MARK: Screens & coordinates

    private func rebuildScreens() {
        let wasActive = isActive
        if wasActive { deactivate() }
        screenlets.forEach { $0.window.close() }
        screenlets = NSScreen.screens.map(Screenlet.init)
        screenlets.forEach {
            $0.pointer.pointerStyle = style
            $0.snap.showsRing = style != .reticle
            $0.spotlight.isHidden = !spotlight
        }
        if wasActive { activate() }
    }

    private func screenlet(containingGlobal p: NSPoint) -> Screenlet? {
        screenlets.first { $0.window.frame.contains(p) }
    }

    private func local(_ global: NSPoint, in s: Screenlet) -> CGPoint {
        CGPoint(x: global.x - s.window.frame.minX, y: global.y - s.window.frame.minY)
    }

    private func localRect(_ global: NSRect, in s: Screenlet) -> CGRect {
        global.offsetBy(dx: -s.window.frame.minX, dy: -s.window.frame.minY)
    }

    private func cgPoint(fromCocoa p: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    private func cocoaRect(fromCG r: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// CGEvent locations use a top-left origin on the primary display;
    /// Cocoa uses bottom-left. Flip through the primary screen's height.
    private func cocoaPoint(fromCG p: CGPoint) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: p.x, y: primaryHeight - p.y)
    }
}
