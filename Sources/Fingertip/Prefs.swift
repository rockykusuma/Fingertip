import AppKit

/// What the hand looks like when the pointer style is Hand.
enum HandKind: String, CaseIterable {
    case symbol, cartoon, glove, emoji

    var title: String {
        switch self {
        case .symbol: return "Menu bar icon"
        case .cartoon: return "Cartoon hand"
        case .glove: return "White glove"
        case .emoji: return "Emoji ☝️"
        }
    }
}

/// Which side of the hand the pointing finger is on. Left matches the menu
/// bar icon; right matches ☝️. Auto flips so the palm sits toward the
/// nearer side edge of the screen.
enum HandSide: String, CaseIterable {
    case left, right, auto

    var title: String {
        switch self {
        case .left: return "Finger on the left"
        case .right: return "Finger on the right"
        case .auto: return "Auto (palm toward nearer edge)"
        }
    }
}

/// Skin tone for the cartoon hand and the emoji. `.classic` is the peach
/// cartoon hand and the yellow emoji.
enum SkinTone: String, CaseIterable {
    case classic, light, mediumLight, medium, mediumDark, dark

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .light: return "Light"
        case .mediumLight: return "Medium light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium dark"
        case .dark: return "Dark"
        }
    }

    var emojiModifier: String {
        ["", "\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"][Self.allCases.firstIndex(of: self)!]
    }

    var skin: NSColor {
        let rgb: [(CGFloat, CGFloat, CGFloat)] = [
            (0.98, 0.80, 0.64), (0.97, 0.86, 0.76), (0.89, 0.73, 0.58),
            (0.78, 0.58, 0.42), (0.60, 0.42, 0.28), (0.40, 0.27, 0.19),
        ]
        let c = rgb[Self.allCases.firstIndex(of: self)!]
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }
}

/// Settings, stored in UserDefaults and edited in the Settings window.
/// Everything reads through here: values used per frame or per stroke apply
/// at once; colours and sizes baked into layers are re-applied by
/// `OverlayController.applyPrefs` on `UserDefaults.didChangeNotification`.
enum Prefs {
    private static var d: UserDefaults { .standard }

    enum Key {
        static let pointerStyle = "pointerStyle"
        static let handKind = "handKind"
        static let skinTone = "skinTone"
        static let handSide = "handSide"
        static let showStick = "showStick"
        static let handSize = "handHeightFraction"
        static let laserColor = "laserColor"
        static let reticleColor = "reticleColor"
        static let snapToElements = "snapToElements"
        static let hideSystemCursor = "hideSystemCursor"
        static let playTapSound = "playTapSound"
        static let inkColor = "inkColor"
        static let inkWidth = "inkWidth"
        static let inkFadeAfter = "inkFadeAfter"
        static let spotlightRadius = "spotlightRadius"
        static let spotlightDim = "spotlightDim"
        static let stampColor = "stampColor"
    }

    static let defaults: [String: Any] = [
        Key.pointerStyle: PointerStyle.hand.rawValue,
        Key.handKind: HandKind.symbol.rawValue,
        Key.skinTone: SkinTone.classic.rawValue,
        Key.handSide: HandSide.left.rawValue,
        Key.showStick: false,
        Key.handSize: 0.11,
        Key.laserColor: "#FF1F1FFF",
        Key.reticleColor: "#4CFF8CFF",
        Key.snapToElements: true,
        Key.hideSystemCursor: true,
        Key.playTapSound: true,
        Key.inkColor: "#FF453BF2",
        Key.inkWidth: 4.0,
        Key.inkFadeAfter: 4.0,
        Key.spotlightRadius: 140.0,
        Key.spotlightDim: 0.72,
        Key.stampColor: "#296BFFFF",
    ]

    /// Call before anything reads a setting (main.swift does).
    static func registerDefaults() { d.register(defaults: defaults) }

    static func resetToDefaults() { defaults.keys.forEach { d.removeObject(forKey: $0) } }

    // MARK: Adjustable

    static var pointerStyle: PointerStyle {
        get { PointerStyle(rawValue: d.string(forKey: Key.pointerStyle) ?? "") ?? .hand }
        set { d.set(newValue.rawValue, forKey: Key.pointerStyle) }
    }
    static var handKind: HandKind { HandKind(rawValue: d.string(forKey: Key.handKind) ?? "") ?? .symbol }
    static var skinTone: SkinTone { SkinTone(rawValue: d.string(forKey: Key.skinTone) ?? "") ?? .classic }
    static var handSide: HandSide { HandSide(rawValue: d.string(forKey: Key.handSide) ?? "") ?? .left }
    /// Draw the stick the hand is held up on (the TinyHand look).
    static var showStick: Bool { d.bool(forKey: Key.showStick) }
    /// Hand height as a fraction of screen height.
    static var handHeightFraction: CGFloat { CGFloat(d.double(forKey: Key.handSize)) }
    static var laserColor: NSColor { color(Key.laserColor) }
    static var reticleColor: NSColor { color(Key.reticleColor) }
    /// Snap the hand to buttons/menu items under the cursor (AX hit test).
    static var snapToElements: Bool {
        get { d.bool(forKey: Key.snapToElements) }
        set { d.set(newValue, forKey: Key.snapToElements) }
    }
    static var hideSystemCursor: Bool { d.bool(forKey: Key.hideSystemCursor) }
    static var playTapSound: Bool { d.bool(forKey: Key.playTapSound) }
    static var inkColor: NSColor { color(Key.inkColor) }
    /// Stroke width for ink, in points.
    static var inkWidth: CGFloat { CGFloat(d.double(forKey: Key.inkWidth)) }
    /// Seconds after a stroke ends before it fades away. 0 = keep until cleared.
    static var inkFadeAfter: TimeInterval { d.double(forKey: Key.inkFadeAfter) }
    /// Spotlight hole radius in points, and how dark the rest of the screen gets.
    static var spotlightRadius: CGFloat { CGFloat(d.double(forKey: Key.spotlightRadius)) }
    static var spotlightDim: CGFloat { CGFloat(d.double(forKey: Key.spotlightDim)) }
    static var stampColor: NSColor { color(Key.stampColor) }

    static func color(_ key: String) -> NSColor {
        NSColor(hex: d.string(forKey: key) ?? "") ?? NSColor(hex: defaults[key] as? String ?? "") ?? .systemRed
    }

    // MARK: Fixed (tuning knobs, not in Settings)

    static let inkFadeDuration: TimeInterval = 0.8
    /// Laser dot diameter in points.
    static let laserDiameter: CGFloat = 18
    /// Lock-on brackets: idle box size, per-frame ease, and how long a lock is
    /// held after leaving an element (so neighbours glide).
    static let reticleIdleSize: CGFloat = 26
    static let reticleEase: CGFloat = 0.22
    static let reticleGrace: CFTimeInterval = 0.35
    static let stampDiameter: CGFloat = 28
    /// A press that moves less than this many points is a tap, not a drag.
    static let tapSlop: CGFloat = 6
    /// How fast the hand eases toward its goal each frame (0...1).
    static let handEase: CGFloat = 0.35

    // Palette for the hand.
    static let outline = NSColor(calibratedWhite: 0.12, alpha: 1)
    static let rod = NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.22, alpha: 1)
}

extension NSColor {
    /// "#RRGGBB" or "#RRGGBBAA", sRGB.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let rgba = s.count == 6 ? (v << 8) | 0xFF : v
        self.init(srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255, green: CGFloat((rgba >> 16) & 0xFF) / 255,
                  blue: CGFloat((rgba >> 8) & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let parts = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
            .map { String(format: "%02X", Int(round(max(0, min(1, $0)) * 255))) }
        return "#" + parts.joined()
    }
}
