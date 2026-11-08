import AppKit
import QuartzCore

enum PointerStyle: CaseIterable {
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

/// Draws the pointer: a cartoon hand on a stick that reaches up from the
/// bottom of the screen to the cursor, or a glowing laser dot.
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
    private let laserGlow = CAShapeLayer()
    private let laserDot = CAShapeLayer()
    private let reticle = ReticleLayer()

    private var handHeight: CGFloat = 120
    private var gripX: CGFloat = 0
    private var hasGrip = false
    private var lastCursor: CGPoint = .zero

    override init() {
        super.init()
        masksToBounds = false
        buildHand()
        buildRod()
        buildLaser()
        reticle.zPosition = 6
        addSublayer(reticle)
        applyStyle()
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    func configure(forScreenSize size: CGSize) {
        handHeight = max(70, size.height * Prefs.handHeightFraction)
        buildHand()
        buildRod()
    }

    /// Called every frame with the cursor in this layer's coordinates.
    func update(cursor: CGPoint, in bounds: CGRect, animated: Bool) {
        lastCursor = cursor
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
        let angle = atan2(dy, dx) - .pi / 2

        handGroup.position = cursor
        handGroup.transform = CATransform3DMakeRotation(angle, 0, 0, 1)

        // Where the stick meets the hand: bottom of the cuff, in local space.
        let baseLocal = CGPoint(x: 0.10 * h, y: -0.98 * h)
        let base = CGPoint(
            x: cursor.x + baseLocal.x * cos(angle) - baseLocal.y * sin(angle),
            y: cursor.y + baseLocal.x * sin(angle) + baseLocal.y * cos(angle)
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
        rodOutline.isHidden = !hand
        rod.isHidden = !hand
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
        laserGlow.fillColor = Prefs.laserColor.withAlphaComponent(0.25).cgColor
        laserGlow.shadowColor = Prefs.laserColor.cgColor
        laserGlow.shadowOpacity = 0.9
        laserGlow.shadowRadius = d * 0.8
        laserGlow.shadowOffset = .zero

        laserDot.path = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil)
        laserDot.fillColor = Prefs.laserColor.cgColor
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

    private func buildHand() {
        let h = handHeight
        pressGroup.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Group bounds in local space: tip at (0,0), hand hangs below.
        let boundsRect = CGRect(x: -0.55 * h, y: -1.08 * h, width: 1.15 * h, height: 1.14 * h)
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
        if handGroup.superlayer == nil { addSublayer(handGroup) }

        let lineWidth = max(1.5, h * 0.028)

        func shape(_ path: CGPath, fill: NSColor, zPos: CGFloat) {
            let layer = CAShapeLayer()
            layer.path = path
            layer.fillColor = fill.cgColor
            layer.strokeColor = Prefs.outline.cgColor
            layer.lineWidth = lineWidth
            layer.lineJoin = .round
            layer.zPosition = zPos
            pressGroup.addSublayer(layer)
        }

        func capsule(from a: CGPoint, to b: CGPoint, width w: CGFloat) -> CGPath {
            // A rounded line as a filled shape.
            let p = CGMutablePath()
            p.move(to: a)
            p.addLine(to: b)
            return p.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
        }

        // Cuff (sleeve) at the bottom.
        let cuff = CGPath(
            roundedRect: CGRect(x: -0.30 * h, y: -1.02 * h, width: 0.78 * h, height: 0.16 * h),
            cornerWidth: 0.05 * h, cornerHeight: 0.05 * h, transform: nil
        )
        shape(cuff, fill: NSColor.white, zPos: 0)

        // Palm.
        let palm = CGPath(
            roundedRect: CGRect(x: -0.22 * h, y: -0.95 * h, width: 0.62 * h, height: 0.52 * h),
            cornerWidth: 0.14 * h, cornerHeight: 0.14 * h, transform: nil
        )
        shape(palm, fill: Prefs.skin, zPos: 1)

        // Thumb, sticking out to the left and slightly up.
        shape(capsule(from: CGPoint(x: -0.16 * h, y: -0.70 * h),
                      to: CGPoint(x: -0.38 * h, y: -0.50 * h),
                      width: 0.17 * h),
              fill: Prefs.skin, zPos: 2)

        // Three curled fingers along the top of the palm.
        for (i, x) in [0.12, 0.26, 0.38].enumerated() {
            let r = (0.095 - CGFloat(i) * 0.008) * h
            let center = CGPoint(x: x * h, y: (-0.46 - CGFloat(i) * 0.02) * h)
            let knuckle = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r), transform: nil)
            shape(knuckle, fill: Prefs.skin, zPos: 3 + CGFloat(i))
        }

        // Index finger pointing up, fingertip at the origin.
        shape(capsule(from: CGPoint(x: 0, y: -0.08 * h),
                      to: CGPoint(x: 0, y: -0.60 * h),
                      width: 0.17 * h),
              fill: Prefs.skin, zPos: 7)

        // Soft shadow under the whole hand.
        handGroup.shadowColor = NSColor.black.cgColor
        handGroup.shadowOpacity = 0.28
        handGroup.shadowRadius = h * 0.05
        handGroup.shadowOffset = CGSize(width: 0, height: -h * 0.03)
    }
}
