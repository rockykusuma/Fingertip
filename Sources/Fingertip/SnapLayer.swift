import AppKit
import QuartzCore

/// Rounded outline around the snapped element plus a small label pill
/// ("Button · Save") above it.
final class SnapLayer: CALayer {
    private let ring = CAShapeLayer()
    private let pill = CALayer()
    private let text = CATextLayer()
    private let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private var last: (CGRect, String)?
    /// Off when the lock-on brackets already outline the element.
    var showsRing = true { didSet { ring.isHidden = !showsRing } }

    override init() {
        super.init()
        masksToBounds = false
        isHidden = true
        ring.fillColor = nil
        ring.lineWidth = 2
        pill.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.92).cgColor
        pill.cornerRadius = 7
        text.font = font
        text.fontSize = font.pointSize
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.truncationMode = .end
        pill.addSublayer(text)
        addSublayer(ring)
        addSublayer(pill)
        applyPrefs()
    }

    func applyPrefs() {
        ring.strokeColor = Prefs.inkColor.cgColor
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func configure(scale: CGFloat) {
        text.contentsScale = scale
    }

    /// `frame` is in this layer's coordinates (bottom-left origin).
    func show(frame f: CGRect, label: String) {
        if !isHidden, let last, last.0 == f, last.1 == label { return }
        last = (f, label)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        isHidden = false
        let r = f.insetBy(dx: -4, dy: -4)
        ring.path = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)

        text.string = label
        pill.isHidden = label.isEmpty
        let w = min(320, (label as NSString).size(withAttributes: [.font: font]).width + 20)
        let h: CGFloat = 22
        text.frame = CGRect(x: 0, y: (h - font.pointSize - 4) / 2, width: w, height: font.pointSize + 4)
        pill.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        // Above the element, nudged inside the screen; below if there's no room.
        var x = r.midX, y = r.maxY + 8 + h / 2
        if y + h / 2 > bounds.maxY { y = r.minY - 8 - h / 2 }
        x = max(w / 2 + 4, min(bounds.maxX - w / 2 - 4, x))
        pill.position = CGPoint(x: x, y: y)
    }

    func hide() {
        isHidden = true
    }
}
