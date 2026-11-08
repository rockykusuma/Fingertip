import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private let tap = InputTap()
    private let hotKeys = HotKeys()
    private let settings = SettingsWindow()
    private var statusItem: NSStatusItem!
    private var escapeHotKey: UInt32?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireInputTap()
        registerHotKeys()
        observeOwnWindows()
        TapSound.prepare()

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
    }

    /// Keep the tap's pass-through rects in step with our own windows: the
    /// status item shifts as other menu bar icons come and go, and Settings,
    /// the colour panel and alerts open, move and close.
    private func observeOwnWindows() {
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
            NSWindow.didChangeOcclusionStateNotification, NSApplication.didChangeScreenParametersNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // After the change lands (willClose fires while still visible).
                DispatchQueue.main.async { self?.updatePassThrough() }
            }
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
        menu.autoenablesItems = false
        menu.addItem(.separator())
        if !InputTap.hasAccessibility {
            add("Grant Accessibility Permission…", #selector(openAccessibility))
            menu.addItem(.separator())
        }
        add("Settings…", #selector(openSettings))
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

    @objc private func clearInk() {
        overlay.clearInk()
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Wiring

    private func wireInputTap() {
        tap.onPress = { [weak self] p, through in self?.overlay.press(atCG: p, throughToApp: through) }
        tap.onRelease = { [weak self] p in self?.overlay.release(atCG: p) }
        tap.onPressure = { [weak self] p in self?.overlay.pressure(p) }
    }

    private func registerHotKeys() {
        hotKeys.register(.ctrlOpt(HotKeys.Key.h)) { [weak self] in self?.toggle() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.x)) { [weak self] in self?.clearInk() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.l)) { [weak self] in self?.toggleStyle() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.s)) { [weak self] in self?.toggleSpotlight() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.a)) { [weak self] in self?.toggleSnap() }
        hotKeys.register(.ctrlOpt(HotKeys.Key.n)) { [weak self] in self?.toggleStepStamps() }
    }

    /// Let clicks reach our own windows while the pointer is on: the menu bar
    /// item, Settings, the colour panel, alerts. The overlay windows ignore
    /// the mouse, so every visible window that doesn't is one of these.
    /// ponytail: a rect, not occlusion-aware; another app's window covering
    /// part of Settings gets clicks there too. Fine for a tool you face.
    private func updatePassThrough() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var windows = NSApp.windows.filter { $0.isVisible && !$0.ignoresMouseEvents }
        if let item = statusItem.button?.window, !windows.contains(item) { windows.append(item) }
        // Cocoa (bottom-left) → CG (top-left) coordinates.
        tap.passThroughRects = windows.map {
            CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
    }
}
