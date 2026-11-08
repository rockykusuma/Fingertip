import AudioToolbox
import Foundation

/// A short "pop" when the hand taps. Uses System Sound Services, which is
/// made for UI clicks: playing returns immediately. NSSound blocked the main
/// thread for ~0.5 s on the first tap while Core Audio started up, freezing
/// the first stroke, and ~15–20 ms on every tap after that.
enum TapSound {
    private static let soundID: SystemSoundID? = {
        var id: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff") as CFURL
        return AudioServicesCreateSystemSoundID(url, &id) == noErr ? id : nil
    }()

    /// Loads the sound at launch so even the first tap costs nothing.
    static func prepare() { _ = soundID }

    static func play() {
        guard Prefs.playTapSound, let soundID else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}
