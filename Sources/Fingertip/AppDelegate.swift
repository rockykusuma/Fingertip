import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private let tap = InputTap()
    private let hotKeys = HotKeys()
    private let voice = VoiceControl()
    private var statusItem: NSStatusItem!
    private var escapeHotKey: UInt32?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireInputTap()
        wireVoice()
        registerHotKeys()

        if !InputTap.hasAccessibility {
            InputTap.requestAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.deactivate()
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: "Fingertip")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshStatusIcon()
        // The item shifts when other menu bar icons come and go.
        for name in [NSWindow.didMoveNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: name == NSWindow.didMoveNotification ? button.window : nil, queue: .main
            ) { [weak self] _ in self?.updatePassThrough() }
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        add(overlay.isActive ? "Hide Pointer  ⌃⌥H" : "Show Pointer  ⌃⌥H", #selector(toggle))
        add("Pointer: \(overlay.style.title) → \(overlay.style.next.title)  ⌃⌥L", #selector(toggleStyle))
        add(overlay.spotlight ? "Spotlight Off  ⌃⌥S" : "Spotlight On  ⌃⌥S", #selector(toggleSpotlight))
        add(overlay.snap ? "Snap to Elements: On  ⌃⌥A" : "Snap to Elements: Off  ⌃⌥A", #selector(toggleSnap))
        add(overlay.stepStamps ? "Step Stamps: On  ⌃⌥N" : "Step Stamps: Off  ⌃⌥N", #selector(toggleStepStamps))
        add("Clear Drawing & Stamps  ⌃⌥X", #selector(clearInk))
        menu.addItem(.separator())
        add(overlay.isRecording ? "Stop Recording  ⌃⌥R" : "Start Recording  ⌃⌥R", #selector(toggleRecording))
        let replay = menu.addItem(withTitle: "Replay Last Recording  ⌃⌥P", action: #selector(replayLast), keyEquivalent: "")
        replay.target = self
        replay.isEnabled = Recording.loadLast() != nil
        menu.autoenablesItems = false
        add(voice.isListening ? "Voice Control Off  ⌃⌥V" : "Voice Control On  ⌃⌥V", #selector(toggleVoice))
        menu.addItem(.separator())
        if !InputTap.hasAccessibility {
            add("Grant Accessibility Permission…", #selector(openAccessibility))
            menu.addItem(.separator())
        }
        let quit = menu.addItem(withTitle: "Quit Fingertip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        // performClick blocks for the menu's tracking loop; the tap would
        // swallow every click on the menu items, so lift it meanwhile.
        tap.isEnabled = false
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        // The menu item may have toggled the pointer; follow the overlay, not the old value.
        tap.isEnabled = overlay.isActive
    }

    private func refreshStatusIcon() {
        let name = overlay.isRecording ? "record.circle.fill"
            : voice.isListening ? "mic.fill" : "hand.point.up.left.fill"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Fingertip")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.appearsDisabled = !overlay.isActive
    }

    // MARK: Actions

    @objc private func toggle() {
        if overlay.isActive {
            deactivate()
        } else {
            activate()
        }
    }

    private func activate() {
        guard InputTap.hasAccessibility else {
            InputTap.requestAccessibility()
            let alert = NSAlert()
            alert.messageText = "Fingertip needs Accessibility access"
            alert.informativeText = "It turns your clicks into taps of the hand instead of clicks on what's underneath. Enable Fingertip in System Settings → Privacy & Security → Accessibility, then try again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { openAccessibility() }
            return
        }
        if !tap.isInstalled, !tap.install() {
            NSLog("Fingertip: could not create event tap")
            return
        }
        updatePassThrough()
        tap.isEnabled = true
        overlay.activate()
        escapeHotKey = hotKeys.register(.init(code: HotKeys.Key.escape, modifiers: 0)) { [weak self] in
            self?.overlay.clearInk()
            self?.deactivate()
        }
        refreshStatusIcon()
    }

    private func deactivate() {
        tap.isEnabled = false
        overlay.deactivate()
        if let id = escapeHotKey { hotKeys.unregister(id); escapeHotKey = nil }
        refreshStatusIcon()
    }

    @objc private func toggleStyle() {
        overlay.style = overlay.style.next
    }

    @objc private func toggleSpotlight() {
        overlay.spotlight.toggle()
        if !overlay.isActive { toggle() }
    }

    @objc private func toggleStepStamps() {
        overlay.stepStamps.toggle()
        if !overlay.isActive { toggle() }
    }

    @objc private func toggleSnap() {
        overlay.snap.toggle()
    }

    @objc private func toggleRecording() {
        if overlay.isRecording {
            overlay.stopRecording()
        } else {
            if !overlay.isActive { activate() }
            guard overlay.isActive else { return }
            overlay.startRecording()
        }
        refreshStatusIcon()
    }

    @objc private func toggleVoice() {
        voice.isListening ? voice.stop() : voice.start()
    }

    @objc private func replayLast() {
        guard let rec = Recording.loadLast() else { NSSound.beep(); return }
        if !overlay.isActive { activate() }
        guard overlay.isActive else { return }
        overlay.startReplay(rec)
    }

    @objc private func clearInk() {
        overlay.clearInk()
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Wiring

    private func wireInputTap() {
        tap.onPress = { [weak self] p in self?.overlay.press(atCG: p) }
        tap.onRelease = { [weak self] p in self?.overlay.release(atCG: p) }
        tap.onPressure = { [weak self] p in self?.overlay.pressure(p) }
    }

    private func wireVoice() {
        voice.onStateChange = { [weak self] in self?.refreshStatusIcon() }
        voice.onCommand = { [weak self] cmd in
            guard let self else { return }
            switch cmd {
            case .pointer(let on): if on != overlay.isActive { toggle() }
            case .tap: overlay.tap()
            case .spotlight(let on):
                if !overlay.isActive { activate() }
                overlay.spotlight = on
            case .laser: overlay.style = .laser
            case .hand: overlay.style = .hand
            case .reticle: overlay.style = .reticle
            case .clear: overlay.clearInk()
            case .stamps(let on):
                if on != overlay.stepStamps { toggleStepStamps() }
            case .record(let on): if on != overlay.isRecording { toggleRecording() }
            case .replay: replayLast()
            case .point(let name):
                if !overlay.isActive { activate() }
                overlay.point(at: name)
            case .stopListening: voice.stop()
            }
        }
    }

    private func registerHotKeys() {
        hotKeys.register(.ctrlOpt(HotKeys.Key.h)) { [weak self] in self?.toggle() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.x)) { [weak self] in self?.clearInk() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.l)) { [weak self] in self?.toggleStyle() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.s)) { [weak self] in self?.toggleSpotlight() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.a)) { [weak self] in self?.toggleSnap() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.r)) { [weak self] in self?.toggleRecording() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.p)) { [weak self] in self?.replayLast() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.v)) { [weak self] in self?.toggleVoice() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.n)) { [weak self] in self?.toggleStepStamps() }
    }

    /// Let clicks on our own menu bar item through the tap so the user can
    /// always reach the menu while the pointer is on.
    private func updatePassThrough() {
        guard let window = statusItem.button?.window else { tap.passThroughRects = []; return }
        let f = window.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // Cocoa (bottom-left) → CG (top-left) coordinates.
        let cg = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        tap.passThroughRects = [cg]
    }
}
