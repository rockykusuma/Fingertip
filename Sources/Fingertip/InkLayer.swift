import AppKit
import QuartzCore

/// Freehand drawing, straight arrows and highlighter strokes. Each stroke
/// is a group of CAShapeLayer segments; for the pen a new segment starts
/// whenever Force Touch pressure moves the width enough to notice, so a
/// stroke swells and thins as you press.
/// ponytail: fixed-width segments with round caps, not a true variable-width
/// ribbon. Upgrade to a filled outline path if the joins ever show.
final class InkLayer: CALayer {
    enum Kind { case pen, arrow, highlighter }

    private var strokes: [CALayer] = []
    private var currentStroke: CALayer?
    private var current: CAShapeLayer?
    private var currentPath = CGMutablePath()
    private var kind: Kind = .pen
    private var start: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var currentWidth: CGFloat = 0

    var isDrawing: Bool { current != nil }
    /// True once nothing is left on screen (fading strokes no longer count).
    var isEmpty: Bool { strokes.isEmpty }
    /// Called when a stroke is added or starts to leave.
    var onChange: (() -> Void)?

    override init() {
        super.init()
        masksToBounds = false
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func begin(at p: CGPoint, width: CGFloat, kind: Kind = .pen) {
        let group = CALayer()
        addSublayer(group)
        strokes.append(group)
        onChange?()
        currentStroke = group
        self.kind = kind
        start = p
        lastPoint = p
        switch kind {
        case .pen: startSegment(width: width, dot: true)
        case .arrow: startSegment(width: width * 1.25, dot: false)
        case .highlighter: startSegment(width: Prefs.highlighterWidth, dot: true)
        }
    }

    /// Force Touch: 0...1. Swaps to a new segment if the width changes by ≥ 0.75pt.
    func setPressure(_ pressure: CGFloat) {
        guard current != nil, kind == .pen else { return }
        let w = Prefs.inkWidth * (0.6 + 1.9 * max(0, min(1, pressure)))
        if abs(w - currentWidth) >= 0.75 { startSegment(width: w, dot: false) }
    }

    private func startSegment(width: CGFloat, dot: Bool) {
        if let current { currentPath.addLine(to: lastPoint); current.path = currentPath }
        let highlighter = kind == .highlighter
        let color = highlighter ? Prefs.highlighterColor.withAlphaComponent(0.4) : Prefs.inkColor
        let shape = CAShapeLayer()
        shape.strokeColor = color.cgColor
        shape.fillColor = nil
        shape.lineWidth = width
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.shadowColor = color.cgColor
        shape.shadowOpacity = highlighter ? 0 : 0.35
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
        if kind == .arrow {
            // Straight from the press point to here, rebuilt every move.
            currentPath = Self.arrowPath(from: start, to: p, width: currentWidth)
        } else {
            // Quadratic smoothing through midpoints keeps strokes from looking jagged.
            let mid = CGPoint(x: (lastPoint.x + p.x) / 2, y: (lastPoint.y + p.y) / 2)
            currentPath.addQuadCurve(to: mid, control: lastPoint)
        }
        lastPoint = p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        current.path = currentPath
        CATransaction.commit()
    }

    func end() {
        if let current {
            if kind == .arrow {
                // Shift-click without a drag: no arrow.
                if hypot(lastPoint.x - start.x, lastPoint.y - start.y) < 4, let stroke = currentStroke {
                    stroke.removeFromSuperlayer()
                    strokes.removeAll { $0 === stroke }
                    onChange?()
                    currentStroke = nil
                }
            } else {
                currentPath.addLine(to: lastPoint)
                current.path = currentPath
            }
        }
        current = nil
        if let stroke = currentStroke, Prefs.inkFadeAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Prefs.inkFadeAfter) { [weak self, weak stroke] in
                guard let self, let stroke else { return }
                self.fade([stroke], duration: Prefs.inkFadeDuration)
            }
        }
        currentStroke = nil
    }

    /// A shaft from `a` to `b` with an open arrowhead at `b`, sized to the
    /// line width and never longer than half the shaft.
    static func arrowPath(from a: CGPoint, to b: CGPoint, width: CGFloat) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0.5 else { return path }
        let head = min(max(12, width * 4.5), length * 0.5)
        let angle = atan2(b.y - a.y, b.x - a.x)
        for side: CGFloat in [-1, 1] {
            let t = angle + .pi - side * .pi / 7
            path.move(to: b)
            path.addLine(to: CGPoint(x: b.x + head * cos(t), y: b.y + head * sin(t)))
        }
        return path
    }

    private func fade(_ layers: [CALayer], duration: TimeInterval) {
        strokes.removeAll { l in layers.contains { $0 === l } }
        onChange?()
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        layers.forEach { $0.opacity = 0 }
        CATransaction.setCompletionBlock { layers.forEach { $0.removeFromSuperlayer() } }
        CATransaction.commit()
    }

    func clear() {
        end()
        fade(strokes, duration: 0.25)
    }
}
