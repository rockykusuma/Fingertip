import AppKit
import QuartzCore

/// Freehand drawing. Each stroke is its own CAShapeLayer so a stroke in
/// progress can be extended cheaply without re-rendering older ones.
final class InkLayer: CALayer {
    private var strokes: [CAShapeLayer] = []
    private var current: CAShapeLayer?
    private var currentPath = CGMutablePath()
    private var lastPoint: CGPoint = .zero

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
        currentPath.move(to: p)
        // A dot for a click-without-drag.
        currentPath.addLine(to: CGPoint(x: p.x + 0.01, y: p.y))
        shape.path = currentPath
        addSublayer(shape)
        strokes.append(shape)
        current = shape
        lastPoint = p
    }

    func extend(to p: CGPoint) {
        guard let current else { return }
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
