import AppKit
import QuartzCore

/// The ring that shows where a click landed in click-through mode, so
/// viewers see each click even though the app underneath handles it.
enum ClickRipple {
    /// `p` is in `layer`'s coordinates.
    static func add(to layer: CALayer, at p: CGPoint) {
        let r: CGFloat = 26
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        ring.position = p
        ring.fillColor = Prefs.inkColor.withAlphaComponent(0.18).cgColor
        ring.strokeColor = Prefs.inkColor.cgColor
        ring.lineWidth = 3
        ring.opacity = 0  // final state; the animation runs from visible to this
        layer.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.25
        scale.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.95
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }
}
