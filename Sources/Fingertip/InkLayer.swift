import AppKit
import QuartzCore

/// Freehand drawing. Each stroke is a group of CAShapeLayer segments; a
/// new segment starts whenever Force Touch pressure moves the width enough
/// to notice, so a stroke swells and thins as you press.
/// ponytail: fixed-width segments with round caps, not a true variable-width
/// ribbon. Upgrade to a filled outline path if the joins ever show.
final class InkLayer: CALayer {
    private var strokes: [CALayer] = []
    private var currentStroke: CALayer?
    private var current: CAShapeLayer?
    private var currentPath = CGMutablePath()
    private var lastPoint: CGPoint = .zero
    private var currentWidth: CGFloat = 0

    var isDrawing: Bool { current != nil }

    override init() {
        super.init()
        masksToBounds = false
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func begin(at p: CGPoint, width: CGFloat) {
        let group = CALayer()
        addSublayer(group)
        strokes.append(group)
        currentStroke = group
        lastPoint = p
        startSegment(width: width, dot: true)
    }

    /// Force Touch: 0...1. Swaps to a new segment if the width changes by ≥ 0.75pt.
    func setPressure(_ pressure: CGFloat) {
        guard current != nil else { return }
        let w = Prefs.inkWidth * (0.6 + 1.9 * max(0, min(1, pressure)))
        if abs(w - currentWidth) >= 0.75 { startSegment(width: w, dot: false) }
    }

    private func startSegment(width: CGFloat, dot: Bool) {
        if let current { currentPath.addLine(to: lastPoint); current.path = currentPath }
        let shape = CAShapeLayer()
        shape.strokeColor = Prefs.inkColor.cgColor
        shape.fillColor = nil
        shape.lineWidth = width
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.shadowColor = Prefs.inkColor.cgColor
        shape.shadowOpacity = 0.35
        shape.shadowRadius = width * 0.6
        shape.shadowOffset = .zero
        currentPath = CGMutablePath()
        currentPath.move(to: lastPoint)
        // A dot for a click-without-drag.
        if dot { currentPath.addLine(to: CGPoint(x: lastPoint.x + 0.01, y: lastPoint.y)) }
        shape.path = currentPath
        currentStroke?.addSublayer(shape)
        current = shape
        currentWidth = width
    }

    func extend(to p: CGPoint) {
        guard let current, hypot(p.x - lastPoint.x, p.y - lastPoint.y) >= 0.5 else { return }
        // Quadratic smoothing through midpoints keeps strokes from looking jagged.
        let mid = CGPoint(x: (lastPoint.x + p.x) / 2, y: (lastPoint.y + p.y) / 2)
        currentPath.addQuadCurve(to: mid, control: lastPoint)
        lastPoint = p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        current.path = currentPath
        CATransaction.commit()
    }

    func end() {
        if let current { currentPath.addLine(to: lastPoint); current.path = currentPath }
        current = nil
        currentStroke = nil
    }

    func clear() {
        end()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        for s in strokes {
            s.opacity = 0
        }
        CATransaction.setCompletionBlock { [strokes] in
            strokes.forEach { $0.removeFromSuperlayer() }
        }
        CATransaction.commit()
        strokes.removeAll()
    }
}
