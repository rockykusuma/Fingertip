import AppKit
import CoreGraphics

/// A session-level CGEvent tap that, while enabled, swallows left-button
/// events so a click becomes a "tap" of the hand rather than a click on
/// whatever is underneath. Right/middle buttons pass through untouched.
/// Hold ⌘ while pressing to click through: that press (and its drag and
/// release) reaches the app as a plain click with ⌘ removed, and the
/// callbacks still fire so the hand can show it.
///
/// Requires Accessibility permission. Runs on its own thread so a busy
/// main thread can never stall the tap (the WindowServer disables taps
/// whose callbacks are too slow).
final class InputTap {
    // Delivered on the main thread. The Bool is true for a ⌘ click-through press.
    var onPress: ((CGPoint, Bool) -> Void)?
    var onRelease: ((CGPoint) -> Void)?
    /// Force Touch pressure, 0...1 (stage 2 reports 1) while a press is held.
    var onPressure: ((CGFloat) -> Void)?

    /// Rects in CG (top-left origin) screen coordinates where left clicks
    /// should still reach the app underneath — e.g. our own menu bar item.
    var passThroughRects: [CGRect] {
        get { lock.withLock { _passThrough } }
        set { lock.withLock { _passThrough = newValue } }
    }

    private(set) var isInstalled = false
    private var tap: CFMachPort?
    private var thread: Thread?
    private let lock = NSLock()
    private var _passThrough: [CGRect] = []
    private var _enabled = false
    private var passingThroughPress = false
    private var swallowingPress = false
    private var clickingThrough = false
    /// Last pressure forwarded; a trackpad reports every tiny change, so only
    /// steps big enough to change the ink's width make the trip to main.
    private var sentPressure: CGFloat = -1

    /// NSEvent.EventType.pressure; CGEventType has no case for it but the tap mask accepts it.
    private static let pressureEventType: UInt32 = 34

    var isEnabled: Bool {
        get { lock.withLock { _enabled } }
        set {
            lock.withLock { _enabled = newValue }
            if let tap { CGEvent.tapEnable(tap: tap, enable: newValue) }
            // A mouse-up that arrives while disabled is never seen, so
            // don't carry press state across an enable/disable cycle.
            if !newValue { passingThroughPress = false; swallowingPress = false; clickingThrough = false }
        }
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func install() -> Bool {
        if isInstalled { return true }
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << Self.pressureEventType)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<InputTap>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            return false
        }
        self.tap = tap
        CGEvent.tapEnable(tap: tap, enable: false)

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [tap] in
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Fingertip.InputTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        self.thread = thread
        isInstalled = true
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The tap gets disabled if we're ever too slow; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, isEnabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        let location = event.location  // CG coordinates: top-left origin
        let pass = Unmanaged.passUnretained(event)

        if type.rawValue == Self.pressureEventType {
            // Only ours while we're swallowing a press; otherwise the app
            // underneath sees it (it never got the mouse-down anyway).
            guard swallowingPress, let ns = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
            let p = ns.stage >= 2 ? 1.0 : CGFloat(ns.pressure)
            guard abs(p - sentPressure) >= 0.05 else { return nil }
            sentPressure = p
            DispatchQueue.main.async { self.onPressure?(p) }
            return nil
        }

        switch type {
        case .leftMouseDown:
            if passThroughRects.contains(where: { $0.contains(location) }) {
                passingThroughPress = true
                return Unmanaged.passUnretained(event)
            }
            passingThroughPress = false
            // ⌘ held: this whole press goes to the app, as a plain click.
            let through = event.flags.contains(.maskCommand)
            clickingThrough = through
            swallowingPress = !through
            sentPressure = -1
            if through { event.flags.remove(.maskCommand) }
            DispatchQueue.main.async { self.onPress?(location, through) }
            return through ? pass : nil
        case .leftMouseDragged:
            if passingThroughPress { return pass }
            if clickingThrough { event.flags.remove(.maskCommand); return pass }
            // Swallowing a drag freezes the system cursor for the rest of the
            // press, and the hand follows the cursor. So let it through as a
            // plain mouse-move: the pointer keeps moving, the app underneath
            // only sees a hover, and the frame loop draws from the new position.
            event.type = .mouseMoved
            return Unmanaged.passUnretained(event)
        case .leftMouseUp:
            swallowingPress = false
            if passingThroughPress {
                passingThroughPress = false
                return Unmanaged.passUnretained(event)
            }
            let through = clickingThrough
            clickingThrough = false
            if through { event.flags.remove(.maskCommand) }
            DispatchQueue.main.async { self.onRelease?(location) }
            return through ? pass : nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
