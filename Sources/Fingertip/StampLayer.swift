import AppKit
import QuartzCore

/// Numbered step badges (1, 2, 3…) dropped where you tap, for walkthroughs
/// and tutorial screenshots. Unlike ink they stay until cleared.
final class StampLayer: CALayer {
    private var badges: [CALayer] = []
    private let font = NSFont.systemFont(ofSize: 14, weight: .heavy)
    var scale: CGFloat = 2

    override init() {
        super.init()
        masksToBounds = false
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /// `p` is the badge centre in this layer's coordinates; nudged on-screen.
    func add(number: Int, at p: CGPoint) {
        let d = Prefs.stampDiameter
        let m = d / 2 + 2
        let badge = CALayer()
        badge.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        badge.position = CGPoint(x: min(max(p.x, m), bounds.maxX - m), y: min(max(p.y, m), bounds.maxY - m))
        badge.cornerRadius = d / 2
        badge.backgroundColor = Prefs.stampColor.cgColor
        badge.borderColor = NSColor.white.cgColor
        badge.borderWidth = 2
        badge.shadowColor = NSColor.black.cgColor
        badge.shadowOpacity = 0.35
        badge.shadowRadius = 3
        badge.shadowOffset = CGSize(width: 0, height: -1)

        let text = CATextLayer()
        let f = font.withSize(number < 10 ? 15 : 12)
        let lineHeight = ceil(f.ascender - f.descender)
        text.string = "\(number)"
        text.font = f
        text.fontSize = f.pointSize
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.contentsScale = scale
        text.frame = CGRect(x: 0, y: (d - lineHeight) / 2, width: d, height: lineHeight)
        badge.addSublayer(text)

        addSublayer(badge)
        badges.append(badge)

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.2
        pop.toValue = 1
        pop.damping = 11
        pop.stiffness = 260
        pop.mass = 0.7
        pop.duration = pop.settlingDuration
        badge.add(pop, forKey: "pop")
    }

    func clear() {
        let gone = badges
        badges.removeAll()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        gone.forEach { $0.opacity = 0 }
        CATransaction.setCompletionBlock { gone.forEach { $0.removeFromSuperlayer() } }
        CATransaction.commit()
    }
}
