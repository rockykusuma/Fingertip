import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window. Every control writes straight to UserDefaults
/// (via @AppStorage); OverlayController picks changes up live.
final class SettingsWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Fingertip Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    typealias K = Prefs.Key
    // Defaults here are only used if registerDefaults hasn't run; the real
    // defaults live in Prefs.defaults.
    @AppStorage(K.pointerStyle) private var style = PointerStyle.hand.rawValue
    @AppStorage(K.handKind) private var handKind = HandKind.cartoon.rawValue
    @AppStorage(K.skinTone) private var skinTone = SkinTone.classic.rawValue
    @AppStorage(K.handSide) private var handSide = HandSide.right.rawValue
    @AppStorage(K.showStick) private var showStick = false
    @AppStorage(K.handSize) private var handSize = 0.11
    @AppStorage(K.laserColor) private var laserColor = ""
    @AppStorage(K.reticleColor) private var reticleColor = ""
    @AppStorage(K.snapToElements) private var snap = true
    @AppStorage(K.hideSystemCursor) private var hideCursor = true
    @AppStorage(K.playTapSound) private var tapSound = true
    @AppStorage(K.inkColor) private var inkColor = ""
    @AppStorage(K.inkWidth) private var inkWidth = 4.0
    @AppStorage(K.inkFadeAfter) private var fadeAfter = 4.0
    @AppStorage(K.spotlightRadius) private var spotRadius = 140.0
    @AppStorage(K.spotlightDim) private var spotDim = 0.72
    @AppStorage(K.stampColor) private var stampColor = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Pointer") {
                Picker("Style", selection: $style) {
                    ForEach(PointerStyle.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Hand", selection: $handKind) {
                    ForEach(HandKind.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Skin tone", selection: $skinTone) {
                    ForEach(SkinTone.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .disabled(handKind == HandKind.glove.rawValue)
                Picker("Pointing hand", selection: $handSide) {
                    ForEach(HandSide.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Show the stick", isOn: $showStick)
                slider("Hand size", $handSize, 0.06...0.20, step: 0.01, "\(Int((handSize * 100).rounded()))%")
                color("Laser colour", $laserColor)
                color("Brackets colour", $reticleColor)
                Toggle("Snap to buttons, menus and links", isOn: $snap)
                Toggle("Hide the system cursor", isOn: $hideCursor)
                Toggle("Tap sound", isOn: $tapSound)
            }
            Section("Drawing") {
                color("Ink colour", $inkColor)
                slider("Line width", $inkWidth, 2...12, step: 0.5, String(format: "%.1f pt", inkWidth))
                slider("Fade after", $fadeAfter, 0...15, step: 1, fadeAfter == 0 ? "Never" : "\(Int(fadeAfter)) s")
            }
            Section("Spotlight") {
                slider("Size", $spotRadius, 60...320, step: 10, "\(Int(spotRadius)) pt")
                slider("Darkness", $spotDim, 0.3...0.9, step: 0.05, "\(Int((spotDim * 100).rounded()))%")
            }
            Section("Step stamps") {
                color("Badge colour", $stampColor)
            }
            Section("General") {
                Toggle("Open Fingertip at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("Fingertip: launch at login failed: \(error)")
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { Prefs.resetToDefaults() }
                }
            }
            Section("Shortcuts") {
                ForEach(Self.shortcuts, id: \.0) { keys, action in
                    LabeledContent(action) { Text(keys).monospaced() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }

    private static let shortcuts: [(String, String)] = [
        ("⌃⌥H", "Pointer on / off"), ("⌃⌥L", "Next pointer style"), ("⌃⌥S", "Spotlight"),
        ("⌃⌥A", "Snap to elements"), ("⌃⌥N", "Step stamps"), ("⌃⌥X", "Clear drawing and stamps"),
        ("⌃⌥R", "Record"), ("⌃⌥P", "Replay last recording"), ("⌃⌥V", "Voice control"),
        ("Esc", "Clear and turn the pointer off"),
    ]

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double, _ text: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: step)
                Text(text).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
            }
        }
    }

    /// Colours are stored as "#RRGGBBAA" strings.
    private func color(_ title: String, _ hex: Binding<String>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: NSColor(hex: hex.wrappedValue) ?? .systemRed) },
            set: { hex.wrappedValue = NSColor($0).hexString }
        ), supportsOpacity: false)
    }
}
