import AppKit

/// A recorded pointer session: timed positions plus press/release events.
/// Positions are global Cocoa coordinates (bottom-left origin) on the
/// primary screen size at record time, so playback can rescale.
struct Recording: Codable {
    struct Sample: Codable {
        var t: TimeInterval
        var x: CGFloat
        var y: CGFloat
        /// "down" or "up"; nil for a plain move.
        var ev: String?
        /// AX label of the snapped element at a "down", used to re-resolve on replay.
        var label: String?
    }

    var primary: CGSize
    var samples: [Sample] = []

    var duration: TimeInterval { samples.last?.t ?? 0 }

    // MARK: Persistence — one "last" recording for now.
    // ponytail: single file; name recordings when there is more than one worth keeping.

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fingertip", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last.json")
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Self.url, options: .atomic) }
    }

    static func loadLast() -> Recording? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Recording.self, from: data)
    }

    /// Position at time `t`, linearly interpolated, rescaled to `screen`.
    func position(at t: TimeInterval, on screen: CGSize) -> NSPoint? {
        guard let first = samples.first else { return nil }
        let sx = screen.width / max(primary.width, 1), sy = screen.height / max(primary.height, 1)
        if t <= first.t { return NSPoint(x: first.x * sx, y: first.y * sy) }
        for (a, b) in zip(samples, samples.dropFirst()) where t < b.t {
            let f = (t - a.t) / max(b.t - a.t, 0.0001)
            return NSPoint(x: (a.x + (b.x - a.x) * f) * sx, y: (a.y + (b.y - a.y) * f) * sy)
        }
        let last = samples[samples.count - 1]
        return NSPoint(x: last.x * sx, y: last.y * sy)
    }
}

/// Accumulates samples while recording.
final class Recorder {
    private(set) var recording: Recording
    private let start = Date()

    init(primary: CGSize) { recording = Recording(primary: primary) }

    func move(_ p: NSPoint) { add(p, ev: nil, label: nil) }
    func down(_ p: NSPoint, label: String?) { add(p, ev: "down", label: label) }
    func up(_ p: NSPoint) { add(p, ev: "up", label: nil) }

    private func add(_ p: NSPoint, ev: String?, label: String?) {
        recording.samples.append(.init(t: Date().timeIntervalSince(start), x: p.x, y: p.y, ev: ev, label: label))
    }
}
