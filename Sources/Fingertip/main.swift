import AppKit

Prefs.registerDefaults()  // before AppDelegate builds anything that reads a setting
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar-only app: no Dock icon, no main window.
app.setActivationPolicy(.accessory)
app.run()
