import AppKit
import Combine
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let showWelcome = Notification.Name("FingertipShowWelcome")
}

/// The first-launch welcome, in three steps like Weekmark's: what Fingertip
/// is, the Accessibility permission (with a live status), and the essentials.
/// Shown once; Settings can open it again.
final class WelcomeWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = WelcomeView { [weak self] in
                self?.window?.close()
                self?.window = nil
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Welcome to Fingertip"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WelcomeView: View {
    let onFinish: () -> Void
    @State private var step: Int
    @State private var trusted = InputTap.hasAccessibility
    @State private var launchAtLogin = true
    // The grant happens in System Settings; poll so the status flips on its own.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(startAt step: Int = 0, onFinish: @escaping () -> Void) {
        _step = State(initialValue: step)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: access
                default: essentials
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle().fill(i == step ? Color.accentColor : .secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                Button(step == 2 ? "Start" : "Continue") {
                    if step < 2 { step += 1 } else { finish() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 520, height: 480)
        .onReceive(poll) { _ in trusted = InputTap.hasAccessibility }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 84))
                .foregroundStyle(Color.accentColor)
            Text("Point at it.").font(.system(size: 34, weight: .bold))
            Text("Fingertip puts a big hand where your cursor is, so everyone watching your screen knows exactly what you mean. Draw, add arrows, highlight and number your steps, then it gets out of the way.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("It lives in the menu bar. There's no Dock icon.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("One permission").font(.title.bold())
            Text("Fingertip needs **Accessibility** access. It uses it for two things, only while the pointer is on:")
                .fixedSize(horizontal: false, vertical: true)
            tip("hand.tap", "Turning your clicks into taps of the hand, so you can point at a button without pressing it.")
            tip("scope", "Reading the name and position of the button under the hand, so it can snap to it and label it.")
            Text("Nothing is recorded or sent anywhere. Fingertip makes no network requests.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if trusted {
                    Label("Access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body.weight(.semibold))
                } else {
                    Button("Open Accessibility Settings") {
                        InputTap.requestAccessibility()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Text("Switch Fingertip on there, then come back.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var essentials: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're set").font(.title.bold())
            tip("keyboard", "Press ⌃⌥H, or click the hand in the menu bar, to turn the pointer on and off.")
            tip("scribble.variable", "Drag to draw. Hold ⇧ for an arrow, ⌥ to highlight. Esc clears it all.")
            tip("command", "Clicks only tap the hand. Hold ⌘ when you want the app to get the click.")
            tip("light.max", "⌃⌥S spotlights the pointer, ⌃⌥N numbers your steps, ⌃⌥L changes the pointer.")
            tip("gearshape", "Right-click the menu bar hand for Settings: the hand, colours, sizes and more.")
            Toggle("Open Fingertip at login", isOn: $launchAtLogin).padding(.top, 4)
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish() {
        if launchAtLogin, SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        Prefs.onboardingDone = true
        onFinish()
    }
}
