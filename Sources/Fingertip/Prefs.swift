import AppKit

/// Phase 0: hardcoded preferences. Promote a value to UserDefaults
/// only once changing it by recompiling gets annoying.
enum Prefs {
    /// Hand height as a fraction of screen height.
    static let handHeightFraction: CGFloat = 0.11
    /// Stroke width for ink, in points.
    static let inkWidth: CGFloat = 4
    static let inkColor = NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 0.95)
    /// Laser dot diameter in points.
    static let laserDiameter: CGFloat = 18
    static let laserColor = NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.12, alpha: 1)
    static let playTapSound = true
    static let hideSystemCursor = true
    /// Spotlight hole radius in points, and how dark the rest of the screen gets.
    static let spotlightRadius: CGFloat = 140
    static let spotlightDim: CGFloat = 0.72
    /// Snap the hand to buttons/menu items under the cursor (AX hit test).
    static let snapToElements = true
    /// How fast the hand eases toward its goal each frame (0...1).
    static let handEase: CGFloat = 0.35

    // Palette for the hand.
    static let skin = NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.64, alpha: 1)
    static let skinShade = NSColor(calibratedRed: 0.86, green: 0.62, blue: 0.47, alpha: 1)
    static let outline = NSColor(calibratedWhite: 0.12, alpha: 1)
    static let rod = NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.22, alpha: 1)
}
