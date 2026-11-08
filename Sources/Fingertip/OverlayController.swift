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
        let snap = SnapLayer()
        let pointer = PointerLayer()

        init(screen: NSScreen) {
            window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
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
            pointer.frame = host.bounds
            snap.frame = host.bounds
            snap.configure(scale: screen.backingScaleFactor)
            pointer.configure(forScreenSize: screen.frame.size)
            host.layer?.addSublayer(spotlight)
            host.layer?.addSublayer(ink)
            host.layer?.addSublayer(snap)
            host.layer?.addSublayer(pointer)
            pointer.isHidden = true
        }
    }

    private(set) var isActive = false
    var style: PointerStyle = .hand {
        didSet { screenlets.forEach { $0.pointer.pointerStyle = style } }
    }
    var spotlight = false {
        didSet {
            screenlets.forEach { $0.spotlight.isHidden = !spotlight; $0.spotlight.update(cursor: nil) }
            if isActive { tick() }
        }
    }

    var snap = Prefs.snapToElements {
        didSet { if !snap { target = nil; screenlets.forEach { $0.snap.hide() } } }
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
    private var screenObserver: NSObjectProtocol?
    private var drawing = false

    init() {
        rebuildScreens()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildScreens() }
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
        screenlets.forEach { $0.snap.hide() }
    }

    func clearInk() {
        screenlets.forEach { $0.ink.clear() }
    }

    // MARK: Input from the event tap (CG coordinates, top-left origin)

    func press(atCG cgPoint: CGPoint) {
        guard isActive else { return }
        // Tap where the hand is; if it is mid-glide between displays, where the cursor is.
        let cursor = cocoaPoint(fromCG: cgPoint)
        var global = shown ?? cursor
        guard let s = screenlet(containingGlobal: global) ?? { global = cursor; return screenlet(containingGlobal: cursor) }()
        else { return }
        let p = local(global, in: s)
        if s !== activeScreenlet {
            activeScreenlet?.pointer.isHidden = true
            activeScreenlet = s
            s.pointer.isHidden = false
        }
        s.pointer.press()
        TapSound.play()
        s.ink.begin(at: p, width: Prefs.inkWidth)
        drawing = true
    }

    func pressure(_ p: CGFloat) {
        guard isActive, drawing, let s = activeScreenlet else { return }
        s.ink.setPressure(p)
    }

    func release(atCG cgPoint: CGPoint) {
        guard isActive else { return }
        screenlets.forEach { $0.pointer.release(); $0.ink.end() }
        drawing = false
    }

    // MARK: Per-frame

    private func tick() {
        let cursor = NSEvent.mouseLocation
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

        // Snap goal: element center while the cursor is inside it.
        var goal = cursor
        if snap, let t = target {
            let f = cocoaRect(fromCG: t.frameCG)
            if f.contains(cursor) {
                goal = NSPoint(x: f.midX, y: f.midY)
                s.snap.show(frame: localRect(f, in: s), label: t.label)
            } else {
                s.snap.hide()
            }
        } else {
            s.snap.hide()
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
        screenlets.forEach { $0.pointer.pointerStyle = style; $0.spotlight.isHidden = !spotlight }
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
