import AppKit
import QuartzCore

/// Dims the whole screen except a circle around the cursor. One shape
/// layer with an even-odd path: screen rect minus the hole.
/// ponytail: hard-edged hole, add a radial gradient mask if the edge looks harsh.
final class SpotlightLayer: CAShapeLayer {
    override init() {
        super.init()
        fillRule = .evenOdd
        isHidden = true
        applyPrefs()
    }

    func applyPrefs() {
        fillColor = NSColor.black.withAlphaComponent(Prefs.spotlightDim).cgColor
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /// `cursor` nil = no hole (screen fully dimmed, used on inactive screens).
    func update(cursor: CGPoint?) {
        let p = CGMutablePath()
        p.addRect(bounds)
        if let c = cursor {
            let r = Prefs.spotlightRadius
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        path = p
        CATransaction.commit()
    }
}
