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
            pointer.configure(forScreenSize: screen.frame.size)
            host.layer?.addSublayer(spotlight)
            host.layer?.addSublayer(ink)
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

    private var screenlets: [Screenlet] = []
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
            $0.pointer.isHidden = true
            $0.window.orderOut(nil)
        }
        activeScreenlet = nil
    }

    func clearInk() {
        screenlets.forEach { $0.ink.clear() }
    }

    // MARK: Input from the event tap (CG coordinates, top-left origin)

    func press(atCG cgPoint: CGPoint) {
        guard isActive, let s = screenlet(containingGlobal: cocoaPoint(fromCG: cgPoint)) else { return }
        let p = local(cocoaPoint(fromCG: cgPoint), in: s)
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

    func drag(toCG cgPoint: CGPoint) {
        guard isActive, drawing, let s = activeScreenlet else { return }
        s.ink.extend(to: local(cocoaPoint(fromCG: cgPoint), in: s))
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
            activeScreenlet = s
            s.pointer.isHidden = false
        }
        let p = local(cursor, in: s)
        s.pointer.update(cursor: p, in: s.host.bounds, animated: true)
        if spotlight { s.spotlight.update(cursor: p) }
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

    /// CGEvent locations use a top-left origin on the primary display;
    /// Cocoa uses bottom-left. Flip through the primary screen's height.
    private func cocoaPoint(fromCG p: CGPoint) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: p.x, y: primaryHeight - p.y)
    }
}
