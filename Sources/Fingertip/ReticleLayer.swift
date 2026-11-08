import AppKit
import QuartzCore

/// Lock-on brackets: four corner brackets that sit as a small box around
/// the fingertip, then clamp onto the snapped element's frame like a
/// targeting display. After being unlocked for a moment they fly in from
/// the screen corners; hopping between neighbours (within the grace period)
/// glides instead. A tap tightens and flashes them.
/// Everything is eased per frame from `update`, no Core Animation timing.
final class ReticleLayer: CALayer {
    private let brackets = CAShapeLayer()
    private let flashLayer = CAShapeLayer()
    private let dot = CAShapeLayer()

    private var rect: CGRect?             // current, eased
    private var held: CGRect?             // lock being shown (survives short gaps)
    private var releaseAt: CFTimeInterval?
    private var pulse: CGFloat = 0

    override init() {
        super.init()
        masksToBounds = false
        for l in [brackets, flashLayer] {
            l.fillColor = nil
            l.lineCap = .round
            l.lineJoin = .round
        }
        brackets.strokeColor = Prefs.reticleColor.cgColor
        brackets.shadowColor = Prefs.reticleColor.cgColor
        brackets.shadowOpacity = 0.8
        brackets.shadowRadius = 4
        brackets.shadowOffset = .zero
        flashLayer.strokeColor = NSColor.white.cgColor
        flashLayer.opacity = 0
        dot.fillColor = Prefs.reticleColor.cgColor
        dot.path = CGPath(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5), transform: nil)
        addSublayer(brackets)
        addSublayer(flashLayer)
        addSublayer(dot)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func flash() { pulse = 1 }

    /// Called every frame (actions already disabled by the caller).
    func update(hand p: CGPoint, lock: CGRect?, in bounds: CGRect) {
        let now = CACurrentMediaTime()
        if let lock {
            // Locking from idle: start from the screen corners and fly in.
            if held == nil { rect = bounds.insetBy(dx: 2, dy: 2) }
            held = lock
            releaseAt = nil
        } else if held != nil {
            if releaseAt == nil { releaseAt = now + Prefs.reticleGrace }
            if let r = releaseAt, now >= r { held = nil; releaseAt = nil }
        }

        let pad = 6 - 4 * pulse   // a tap squeezes them in
        let s = Prefs.reticleIdleSize
        let goal = held?.insetBy(dx: -pad, dy: -pad)
            ?? CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
        let cur = rect ?? goal
        let e = Prefs.reticleEase
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
        let minX = mix(cur.minX, goal.minX), minY = mix(cur.minY, goal.minY)
        let maxX = mix(cur.maxX, goal.maxX), maxY = mix(cur.maxY, goal.maxY)
        let r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        rect = r

        let path = Self.bracketPath(r)
        brackets.path = path
        brackets.lineWidth = 2.5 + 1.5 * pulse
        flashLayer.path = path
        flashLayer.lineWidth = brackets.lineWidth
        flashLayer.opacity = Float(pulse)
        dot.position = p
        pulse = pulse < 0.01 ? 0 : pulse * 0.88
    }

    private static func bracketPath(_ r: CGRect) -> CGPath {
        let arm = max(5, min(18, min(r.width, r.height) * 0.3))
        let path = CGMutablePath()
        // Each corner: an L whose elbow is the corner itself.
        for (cx, cy, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0),
                                 (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            path.move(to: CGPoint(x: cx, y: cy + dy * arm))
            path.addLine(to: CGPoint(x: cx, y: cy))
            path.addLine(to: CGPoint(x: cx + dx * arm, y: cy))
        }
        return path
    }
}
