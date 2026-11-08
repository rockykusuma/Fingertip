// Renders the app icon at 1024×1024: the menu bar hand (SF Symbol
// hand.point.up.left, white under a dark outline) on a blue squircle, with
// a red ripple at the fingertip.  Usage: swift scripts/make-icon.swift out.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let N = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: N, pixelsHigh: N, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: N, height: N)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Squircle tile, macOS icon grid: 824 pt inset by 100, radius ~185, soft drop shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor(srgbRed: 0.24, green: 0.30, blue: 0.86, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(srgbRed: 0.40, green: 0.52, blue: 1.00, alpha: 1),
           ending: NSColor(srgbRed: 0.22, green: 0.24, blue: 0.80, alpha: 1))!.draw(in: shape, angle: -90)

// The hand, rendered on its own so its fingertip can be found from pixels.
// Fill one weight lighter than the outline, each centred at its own size,
// so the white sits cleanly inside the outline (same as PointerLayer).
func symbol(_ name: String, _ weight: NSFont.Weight, _ color: NSColor) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 470, weight: weight).applying(.init(paletteColors: [color])))!
}
let fill = symbol("hand.point.up.left.fill", .regular, .white)
let line = symbol("hand.point.up.left", .semibold, NSColor(white: 0.12, alpha: 1))
let hs = NSSize(width: ceil(max(fill.size.width, line.size.width)), height: ceil(max(fill.size.height, line.size.height)))
let hrep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(hs.width), pixelsHigh: Int(hs.height),
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
hrep.size = hs
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: hrep)
for img in [fill, line] {
    img.draw(in: NSRect(x: (hs.width - img.size.width) / 2, y: (hs.height - img.size.height) / 2,
                        width: img.size.width, height: img.size.height))
}
NSGraphicsContext.restoreGraphicsState()
let data = hrep.bitmapData!
var tip = NSPoint.zero
search: for row in 0..<hrep.pixelsHigh {
    var sum = 0, n = 0
    for x in 0..<hrep.pixelsWide where data[row * hrep.bytesPerRow + x * 4 + 3] > 128 { sum += x; n += 1 }
    if n > 0 { tip = NSPoint(x: CGFloat(sum) / CGFloat(n), y: hs.height - CGFloat(row) - 14); break search }
}

// Place the fingertip up and left of centre, ripple first, hand on top.
let target = NSPoint(x: 360, y: 760)
for (r, w, a) in [(118.0, 16.0, 0.55), (78.0, 20.0, 0.95)] {
    let ring = NSBezierPath(ovalIn: NSRect(x: target.x - r, y: target.y - r, width: 2 * r, height: 2 * r))
    ring.lineWidth = w
    NSColor(srgbRed: 1.0, green: 0.30, blue: 0.25, alpha: a).setStroke()
    ring.stroke()
}
NSGraphicsContext.saveGraphicsState()
let handShadow = NSShadow()
handShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
handShadow.shadowOffset = NSSize(width: 0, height: -10)
handShadow.shadowBlurRadius = 18
handShadow.set()
NSImage(cgImage: hrep.cgImage!, size: hs).draw(at: NSPoint(x: target.x - tip.x, y: target.y - tip.y),
                                              from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
