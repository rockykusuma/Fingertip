import AppKit
import QuartzCore

enum PointerStyle: String, CaseIterable {
    case hand
    case laser
    case reticle

    var title: String {
        switch self {
        case .hand: return "Hand"
        case .laser: return "Laser"
        case .reticle: return "Lock-on Brackets"
        }
    }

    var next: PointerStyle {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Draws the pointer: a hand on a stick that reaches up from the bottom of
/// the screen to the cursor, a glowing laser dot, or lock-on brackets.
///
/// Coordinates are the hosting layer's (origin bottom-left, y up). The hand
/// is built in a local space where the fingertip is (0, 0) and the hand
/// hangs below it; the group is then rotated so the stick looks like it is
/// holding the hand up from wherever the grip is.
final class PointerLayer: CALayer {
    var pointerStyle: PointerStyle = .hand { didSet { applyStyle() } }
    /// Snapped element frame in this layer's coordinates, set before `update`.
    var lockRect: CGRect?

    private let rodOutline = CAShapeLayer()
    private let rod = CAShapeLayer()
    private let handGroup = CALayer()     // position + rotation
    private let pressGroup = CALayer()    // press squash, inside handGroup
    private let artGroup = CALayer()      // the drawing, mirrored for the other hand
    private let laserGlow = CAShapeLayer()
    private let laserDot = CAShapeLayer()
    private let reticle = ReticleLayer()

    private var handHeight: CGFloat = 120
    /// Where the stick meets the hand, in the hand's local space.
    private var baseLocal = CGPoint(x: 0, y: -100)
    private var gripX: CGFloat = 0
    private var hasGrip = false

    private var side: HandSide = .right
    private var showStick = false
    /// Whether the current artwork has its finger on the right as drawn
    /// (the emoji does; the menu bar hand has it on the left).
    private var nativeRight = false
    private var autoRight = true
    /// Horizontal scale of the drawing, eased between 1 and -1 so a flip
    /// turns the hand over instead of jumping.
    private var mirror: CGFloat = 1
    private var hasMirror = false

    override init() {
        super.init()
        masksToBounds = false
        buildLaser()
        reticle.zPosition = 6
        addSublayer(reticle)
        applyPrefs(screenSize: CGSize(width: 1440, height: 900))
        applyStyle()
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Settings

    /// Re-reads size, hand kind, skin tone and colours from Prefs.
    func applyPrefs(screenSize size: CGSize) {
        handHeight = max(70, size.height * Prefs.handHeightFraction)
        side = Prefs.handSide
        showStick = Prefs.showStick
        buildHand()
        buildRod()
        colorLaser()
        reticle.applyPrefs()
        applyStyle()
    }

    // MARK: Layout

    /// Called every frame with the cursor in this layer's coordinates.
    func update(cursor: CGPoint, in bounds: CGRect, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        switch pointerStyle {
        case .laser:
            laserGlow.position = cursor
            laserDot.position = cursor
        case .hand:
            layoutHand(cursor: cursor, in: bounds)
        case .reticle:
            reticle.update(hand: cursor, lock: lockRect, in: bounds)
        }
    }

    private func layoutHand(cursor: CGPoint, in bounds: CGRect) {
        // The grip sits just below the bottom edge and leans toward the
        // cursor, trailing it a little so the stick swings naturally.
        let h = handHeight
        let center = bounds.midX
        let lean = cursor.x + (cursor.x - center) * 0.25
        let target = min(max(lean, bounds.minX - h), bounds.maxX + h)
        if hasGrip {
            gripX += (target - gripX) * 0.10
        } else {
            gripX = target
            hasGrip = true
        }
        let grip = CGPoint(x: gripX, y: bounds.minY - h * 0.3)

        let dx = cursor.x - grip.x
        let dy = cursor.y - grip.y
        // Lean away from the grip. Without a visible stick a full lean looks
        // odd near the edges, so a floating hand stays mostly upright.
        let angle = (atan2(dy, dx) - .pi / 2) * (showStick ? 1 : 0.35)

        handGroup.position = cursor
        handGroup.transform = CATransform3DMakeRotation(angle, 0, 0, 1)

        // Right or left hand. Auto keeps the palm toward the nearer side edge,
        // with a dead zone in the middle so it doesn't flip back and forth.
        let wantRight: Bool
        switch side {
        case .right: wantRight = true
        case .left: wantRight = false
        case .auto:
            let dead = bounds.width * 0.08
            if autoRight, cursor.x > bounds.midX + dead { autoRight = false }
            else if !autoRight, cursor.x < bounds.midX - dead { autoRight = true }
            wantRight = autoRight
        }
        let goal: CGFloat = wantRight == nativeRight ? 1 : -1
        mirror = hasMirror ? mirror + (goal - mirror) * 0.25 : goal
        hasMirror = true
        // Never exactly edge-on, or the hand vanishes for a frame mid-flip.
        let m = abs(mirror) < 0.05 ? (goal > 0 ? 0.05 : -0.05) : mirror
        artGroup.transform = CATransform3DMakeScale(m, 1, 1)

        let bx = baseLocal.x * m, by = baseLocal.y
        let base = CGPoint(
            x: cursor.x + bx * cos(angle) - by * sin(angle),
            y: cursor.y + bx * sin(angle) + by * cos(angle)
        )
        let path = CGMutablePath()
        path.move(to: grip)
        path.addLine(to: base)
        rod.path = path
        rodOutline.path = path
    }

    // MARK: Press feedback

    func press() {
        if pointerStyle == .reticle { reticle.flash() }
        let h = handHeight
        var t = CATransform3DMakeTranslation(0, -0.06 * h, 0)
        t = CATransform3DScale(t, 0.95, 0.92, 1)
        animatePress(to: t, damping: 18, velocity: 10)
    }

    func release() {
        animatePress(to: CATransform3DIdentity, damping: 9, velocity: 6)
    }

    private func animatePress(to transform: CATransform3D, damping: CGFloat, velocity: CGFloat) {
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = pressGroup.presentation()?.transform ?? pressGroup.transform
        spring.toValue = transform
        spring.damping = damping
        spring.stiffness = 300
        spring.mass = 0.6
        spring.initialVelocity = velocity
        spring.duration = spring.settlingDuration
        pressGroup.transform = transform
        pressGroup.add(spring, forKey: "press")
    }

    // MARK: Construction

    private func applyStyle() {
        let hand = pointerStyle == .hand
        rodOutline.isHidden = !hand || !showStick
        rod.isHidden = !hand || !showStick
        handGroup.isHidden = !hand
        laserGlow.isHidden = pointerStyle != .laser
        laserDot.isHidden = pointerStyle != .laser
        reticle.isHidden = pointerStyle != .reticle
    }

    private func buildRod() {
        let h = handHeight
        for (layer, color, width) in [
            (rodOutline, Prefs.outline, h * 0.075),
            (rod, Prefs.rod, h * 0.05),
        ] {
            layer.strokeColor = color.cgColor
            layer.fillColor = nil
            layer.lineWidth = width
            layer.lineCap = .round
            if layer.superlayer == nil { addSublayer(layer) }
        }
        // Keep the hand above the rod.
        rodOutline.zPosition = 1
        rod.zPosition = 2
        handGroup.zPosition = 3
    }

    private func buildLaser() {
        let d = Prefs.laserDiameter
        laserGlow.path = CGPath(ellipseIn: CGRect(x: -d, y: -d, width: d * 2, height: d * 2), transform: nil)
        laserGlow.shadowOpacity = 0.9
        laserGlow.shadowRadius = d * 0.8
        laserGlow.shadowOffset = .zero

        laserDot.path = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil)
        let core = CAShapeLayer()
        let c = d * 0.4
        core.path = CGPath(ellipseIn: CGRect(x: -c / 2, y: -c / 2 + d * 0.08, width: c, height: c), transform: nil)
        core.fillColor = NSColor.white.withAlphaComponent(0.85).cgColor
        laserDot.addSublayer(core)

        laserGlow.zPosition = 4
        laserDot.zPosition = 5
        addSublayer(laserGlow)
        addSublayer(laserDot)
    }

    private func colorLaser() {
        let c = Prefs.laserColor
        laserGlow.fillColor = c.withAlphaComponent(0.25).cgColor
        laserGlow.shadowColor = c.cgColor
        laserDot.fillColor = c.cgColor
    }

    private func buildHand() {
        let h = handHeight
        artGroup.sublayers?.forEach { $0.removeFromSuperlayer() }
        let wasNativeRight = nativeRight

        // Group bounds in local space: tip at (0,0), hand hangs below.
        let boundsRect = CGRect(x: -0.55 * h, y: -1.08 * h, width: 1.20 * h, height: 1.14 * h)
        for g in [handGroup, pressGroup] {
            g.bounds = boundsRect
            g.anchorPoint = CGPoint(
                x: (0 - boundsRect.minX) / boundsRect.width,
                y: (0 - boundsRect.minY) / boundsRect.height
            )
            g.masksToBounds = false
        }
        pressGroup.position = .zero
        if pressGroup.superlayer == nil { handGroup.addSublayer(pressGroup) }
        // Zero-size layer at the tip, so its mirror transform flips about the tip.
        artGroup.bounds = .zero
        artGroup.position = .zero
        if artGroup.superlayer == nil { pressGroup.addSublayer(artGroup) }
        if handGroup.superlayer == nil { addSublayer(handGroup) }

        // Soft shadow under the whole hand.
        handGroup.shadowColor = NSColor.black.cgColor
        handGroup.shadowOpacity = 0.28
        handGroup.shadowRadius = h * 0.05
        handGroup.shadowOffset = CGSize(width: 0, height: -h * 0.03)

        let built: Bool
        switch Prefs.handKind {
        case .symbol: built = buildSymbol(h: h, fill: .white)
        // Same shape as the menu bar icon, in the chosen skin tone.
        case .cartoon: built = buildSymbol(h: h, fill: Prefs.skinTone.skin)
        case .emoji: built = buildEmoji(h: h) || buildSymbol(h: h, fill: .white)
        }
        if !built { NSLog("Fingertip: could not render the hand") }
        // Switching between drawings of opposite hands: keep what's on screen
        // the same hand instead of animating a flip.
        if nativeRight != wasNativeRight { mirror = -mirror }
    }

    /// Apple's ☝️ in the chosen skin tone, positioned by its rendered pixels.
    /// Apple's ☝️ in the chosen skin tone, positioned by its rendered pixels.
    private func buildEmoji(h: CGFloat) -> Bool {
        let tone = Prefs.skinTone
        let glyph = tone == .classic ? "\u{261D}\u{FE0F}" : "\u{261D}" + tone.emojiModifier
        let font = NSFont(name: "AppleColorEmoji", size: h) ?? .systemFont(ofSize: h)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (glyph as NSString).size(withAttributes: attrs)
        guard let s = Self.sprite(size: size, draw: { _ in (glyph as NSString).draw(at: .zero, withAttributes: attrs) })
        else { return false }
        place(s, nativeRight: true)
        return true
    }

    /// The menu bar icon's hand (SF Symbol hand.point.up.left) at pointer
    /// size: `fill` under a dark outline, like the macOS pointing cursor.
    private func buildSymbol(h: CGFloat, fill fillColor: NSColor) -> Bool {
        // The filled and outline symbols don't line up exactly: at equal
        // weights white pokes past the outline in places and leaves gaps in
        // others. A fill one weight lighter, each centred at its own size,
        // sits cleanly inside the outline.
        func symbol(_ name: String, _ weight: NSFont.Weight, _ color: NSColor) -> NSImage? {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: h * 0.8, weight: weight).applying(.init(paletteColors: [color])))
        }
        guard let fill = symbol("hand.point.up.left.fill", .regular, fillColor),
              let line = symbol("hand.point.up.left", .semibold, Prefs.outline)
        else { return false }
        let size = CGSize(width: max(fill.size.width, line.size.width), height: max(fill.size.height, line.size.height))
        guard let s = Self.sprite(size: size, draw: { r in
            for img in [fill, line] {
                img.draw(in: NSRect(x: r.midX - img.size.width / 2, y: r.midY - img.size.height / 2,
                                    width: img.size.width, height: img.size.height))
            }
        }) else { return false }
        place(s, nativeRight: false)
        return true
    }

    private func place(_ s: Sprite, nativeRight: Bool) {
        let layer = CALayer()
        layer.contents = s.image
        layer.frame = CGRect(x: -s.tip.x, y: -s.tip.y, width: s.size.width, height: s.size.height)
        artGroup.addSublayer(layer)
        baseLocal = CGPoint(x: s.base.x - s.tip.x, y: s.base.y - s.tip.y)
        self.nativeRight = nativeRight
    }

    typealias Sprite = (image: CGImage, size: CGSize, tip: CGPoint, base: CGPoint)

    /// Draws into a bitmap and finds the tip (centre of the top-most opaque
    /// pixels) and base (bottom-most), in points with a bottom-left origin,
    /// so any artwork can sit with its fingertip on the cursor.
    static func sprite(size: CGSize, draw: (NSRect) -> Void) -> Sprite? {
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let pw = Int(ceil(size.width * scale)), ph = Int(ceil(size.height * scale))
        guard pw > 0, ph > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData, let image = rep.cgImage else { return nil }

        // Bitmap rows run top-down; alpha is the 4th byte of each pixel.
        func meanOpaqueX(_ row: Int) -> CGFloat? {
            var sum = 0, n = 0
            for x in 0..<pw where data[row * rep.bytesPerRow + x * 4 + 3] > 128 { sum += x; n += 1 }
            return n > 0 ? CGFloat(sum) / CGFloat(n) : nil
        }
        guard let top = (0..<ph).first(where: { meanOpaqueX($0) != nil }),
              let bottom = (0..<ph).reversed().first(where: { meanOpaqueX($0) != nil }),
              let tipX = meanOpaqueX(min(top + Int(3 * scale), bottom)),
              let baseX = meanOpaqueX(bottom)
        else { return nil }
        let tip = CGPoint(x: tipX / scale, y: CGFloat(ph - top) / scale)
        let base = CGPoint(x: baseX / scale, y: CGFloat(ph - bottom) / scale)
        return (image, size, tip, base)
    }
}
