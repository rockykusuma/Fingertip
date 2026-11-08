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
    /// Whether the current drawing is a right hand as drawn (the emoji is;
    /// the cartoon and glove are drawn as a left hand).
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

        switch Prefs.handKind {
        case .cartoon: buildCartoon(h: h, glove: false)
        case .glove: buildCartoon(h: h, glove: true)
        case .emoji:
            if !buildEmoji(h: h) { buildCartoon(h: h, glove: false) }
        }
        // Switching between drawings of opposite hands: keep what's on screen
        // the same hand instead of animating a flip.
        if nativeRight != wasNativeRight { mirror = -mirror }
    }

    /// The cartoon hand (or white glove). Index finger up on the thumb side,
    /// the other three curled to its right, thumb folded across them, so it
    /// reads unmistakably as pointing (like ☝️).
    private func buildCartoon(h: CGFloat, glove: Bool) {
        let lineWidth = max(1.5, h * 0.028)
        let fill = glove ? NSColor(white: 0.98, alpha: 1) : Prefs.skinTone.skin

        func shape(_ path: CGPath, _ fill: NSColor?, _ zPos: CGFloat, width: CGFloat? = nil) {
            let layer = CAShapeLayer()
            layer.path = path
            layer.fillColor = fill?.cgColor
            layer.strokeColor = Prefs.outline.cgColor
            layer.lineWidth = width ?? lineWidth
            layer.lineJoin = .round
            layer.lineCap = .round
            layer.zPosition = zPos
            artGroup.addSublayer(layer)
        }
        func capsule(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.move(to: a)
            p.addLine(to: b)
            return p.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * h, y: y * h) }

        // Cuff: a plain sleeve for the hand, a puffy rolled cuff for the glove.
        let cuff = glove ? CGRect(x: -0.24 * h, y: -1.05 * h, width: 0.86 * h, height: 0.22 * h)
                         : CGRect(x: -0.20 * h, y: -1.02 * h, width: 0.78 * h, height: 0.16 * h)
        shape(CGPath(roundedRect: cuff, cornerWidth: 0.08 * h, cornerHeight: 0.08 * h, transform: nil), .white, 0)
        if glove {
            let fold = CGMutablePath()
            fold.move(to: pt(-0.20, -0.95))
            fold.addLine(to: pt(0.58, -0.95))
            shape(fold, nil, 0.5, width: lineWidth * 0.8)
        }

        // Palm, to the right of the index finger.
        shape(CGPath(roundedRect: CGRect(x: -0.12 * h, y: -0.95 * h, width: 0.62 * h, height: 0.52 * h),
                     cornerWidth: 0.14 * h, cornerHeight: 0.14 * h, transform: nil), fill, 1)

        // Three curled fingers along the top of the palm.
        for (i, x) in [0.175, 0.31, 0.425].enumerated() {
            let r = (0.11 - CGFloat(i) * 0.008) * h
            let c = pt(CGFloat(x), -0.42 - CGFloat(i) * 0.025)
            shape(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil),
                  fill, 2 + CGFloat(i))
        }

        // Glove: three stitch lines on the back.
        if glove {
            for x in [0.17, 0.29, 0.40] {
                let p = CGMutablePath()
                p.move(to: pt(CGFloat(x), -0.80))
                p.addLine(to: pt(CGFloat(x), -0.62))
                shape(p, nil, 5, width: lineWidth * 0.8)
            }
        }

        // Thumb, folded across the curled fingers from the index side.
        shape(capsule(pt(-0.06, -0.70), pt(0.20, -0.60), 0.16 * h), fill, 6)

        // Index finger pointing up, fingertip at the origin.
        shape(capsule(pt(0, -0.085), pt(0, -0.62), 0.17 * h), fill, 7)

        baseLocal = CGPoint(x: cuff.midX, y: cuff.minY + 0.04 * h)
        nativeRight = false
    }

    /// Apple's ☝️ in the chosen skin tone, positioned by its rendered pixels.
    private func buildEmoji(h: CGFloat) -> Bool {
        let tone = Prefs.skinTone
        let glyph = tone == .classic ? "\u{261D}\u{FE0F}" : "\u{261D}" + tone.emojiModifier
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        guard let s = Self.emojiSprite(glyph, fontSize: h, scale: scale) else { return false }
        let layer = CALayer()
        layer.contents = s.image
        layer.frame = CGRect(x: -s.tip.x, y: -s.tip.y, width: s.size.width, height: s.size.height)
        artGroup.addSublayer(layer)
        baseLocal = CGPoint(x: s.base.x - s.tip.x, y: s.base.y - s.tip.y)
        nativeRight = true
        return true
    }

    /// Renders `text` and finds its tip (centre of the top-most opaque pixels)
    /// and base (bottom-most), in points with a bottom-left origin.
    static func emojiSprite(_ text: String, fontSize: CGFloat, scale: CGFloat)
        -> (image: CGImage, size: CGSize, tip: CGPoint, base: CGPoint)?
    {
        let font = NSFont(name: "AppleColorEmoji", size: fontSize) ?? .systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        let pw = Int(ceil(size.width * scale)), ph = Int(ceil(size.height * scale))
        guard pw > 0, ph > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (text as NSString).draw(at: .zero, withAttributes: attrs)
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
