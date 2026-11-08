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
    private var recorder: Recorder?
    var isRecording: Bool { recorder != nil }
    private var replay: (rec: Recording, start: Date, next: Int)?
    var isReplaying: Bool { replay != nil }
    var onReplayFinished: (() -> Void)?
    /// Label of the element the hand is snapped to right now, if any.
    private var snappedLabel: String?
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
        replay = nil
        if recorder != nil { _ = stopRecording() }
        screenlets.forEach { $0.snap.hide() }
    }

    // MARK: Record & replay

    func startRecording() {
        recorder = Recorder(primary: primarySize)
    }

    /// Stops, saves as the last recording, and returns it.
    @discardableResult
    func stopRecording() -> Recording? {
        guard let r = recorder?.recording else { return nil }
        recorder = nil
        r.save()
        return r
    }

    /// Plays `rec` through the hand. Taps that were snapped to an element are
    /// re-resolved first so the replay survives a moved window.
    func startReplay(_ rec: Recording) {
        guard isActive else { return }
        let screen = primarySize
        let primaryHeight = screen.height
        probeQueue.async { [weak self] in
            var rec = rec
            let sx = screen.width / max(rec.primary.width, 1), sy = screen.height / max(rec.primary.height, 1)
            var i = 0
            while i < rec.samples.count {
                let s = rec.samples[i]
                defer { i += 1 }
                guard s.ev == "down", let label = s.label else { continue }
                let cg = CGPoint(x: s.x * sx, y: primaryHeight - s.y * sy)
                guard let t = AXProbe.target(atCG: cg), t.label == label else { continue }
                // ponytail: re-resolves only if the element is still under the
                // recorded point; a bigger move needs a search by label.
                let center = NSPoint(x: t.frameCG.midX, y: primaryHeight - t.frameCG.midY)
                let dx = center.x / sx - s.x, dy = center.y / sy - s.y
                var j = i
                while j < rec.samples.count {  // shift this press through its release
                    rec.samples[j].x += dx; rec.samples[j].y += dy
                    if rec.samples[j].ev == "up" { break }
                    j += 1
                }
            }
            DispatchQueue.main.async { self?.replay = (rec, Date(), 0) }
        }
    }

    private var primarySize: CGSize { NSScreen.screens.first?.frame.size ?? .zero }

    // MARK: Voice

    /// Moves the real cursor onto the named element in the frontmost app, so
    /// the hand follows and snaps to it like any other move.
    func point(at name: String) {
        guard isActive, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        probeQueue.async { [weak self] in
            guard let t = AXProbe.find(titleContaining: name, inApp: pid) else { NSSound.beep(); return }
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                CGWarpMouseCursorPosition(CGPoint(x: t.frameCG.midX, y: t.frameCG.midY))
                CGAssociateMouseAndMouseCursorPosition(1)
                self.target = t
            }
        }
    }

    /// A short press where the hand is.
    func tap() {
        guard isActive, !drawing else { return }
        beginPress(global: shown ?? NSEvent.mouseLocation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.endPress() }
    }

    /// Advances replay to now, firing presses, and returns the cursor to show.
    private func replayCursor() -> NSPoint? {
        guard var r = replay else { return nil }
        let t = Date().timeIntervalSince(r.start)
        let screen = primarySize
        let sx = screen.width / max(r.rec.primary.width, 1), sy = screen.height / max(r.rec.primary.height, 1)
        while r.next < r.rec.samples.count, r.rec.samples[r.next].t <= t {
            let s = r.rec.samples[r.next]
            r.next += 1
            let p = NSPoint(x: s.x * sx, y: s.y * sy)
            if s.ev == "down" { beginPress(global: p) } else if s.ev == "up" { endPress() }
        }
        if t > r.rec.duration + 0.3 {
            replay = nil
            endPress()
            onReplayFinished?()
            return nil
        }
        replay = r
        return r.rec.position(at: t, on: screen)
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
        s.ink.begin(at: p, width: Prefs.inkWidth)
        drawing = true
        recorder?.down(global, label: snappedLabel)
    }

    private func endPress() {
        guard drawing else { return }
        screenlets.forEach { $0.pointer.release(); $0.ink.end() }
        drawing = false
        recorder?.up(shown ?? NSEvent.mouseLocation)
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
        let cursor = replayCursor() ?? NSEvent.mouseLocation
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
        if let recorder, tickCount % 4 == 0 { recorder.move(cursor) }  // ~30 Hz

        // Snap goal: element center while the cursor is inside it. Not while
        // drawing, or a stroke inside a large element could never leave its centre.
        var goal = cursor
        if snap, !drawing, let t = target {
            let f = cocoaRect(fromCG: t.frameCG)
            if f.contains(cursor) {
                goal = NSPoint(x: f.midX, y: f.midY)
                s.snap.show(frame: localRect(f, in: s), label: t.label)
                snappedLabel = t.label
            } else {
                s.snap.hide()
                snappedLabel = nil
            }
        } else {
            s.snap.hide()
            snappedLabel = nil
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
