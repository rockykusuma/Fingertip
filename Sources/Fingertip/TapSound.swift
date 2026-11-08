import AppKit

/// A short click when the hand taps. Uses a system sound for now; swap in
/// a bundled asset later if you want something softer.
enum TapSound {
    private static let sound: NSSound? = {
        guard let s = NSSound(named: "Pop") else { return nil }
        s.volume = 0.5
        return s
    }()

    static func play() {
        guard Prefs.playTapSound, let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
