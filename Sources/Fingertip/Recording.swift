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
    /// `hint` is an index at or just past the segment containing `t` (replay
    /// passes its next-unfired sample), so a frame costs O(1) instead of a scan.
    func position(at t: TimeInterval, on screen: CGSize, from hint: Int = 0) -> NSPoint? {
        guard let first = samples.first else { return nil }
        let sx = screen.width / max(primary.width, 1), sy = screen.height / max(primary.height, 1)
        if t <= first.t { return NSPoint(x: first.x * sx, y: first.y * sy) }
        var k = max(0, min(hint, samples.count) - 1)
        if samples[k].t > t { k = 0 }  // hint ahead of t: rescan
        while k + 1 < samples.count, samples[k + 1].t <= t { k += 1 }
        guard k + 1 < samples.count else { return NSPoint(x: samples[k].x * sx, y: samples[k].y * sy) }
        let a = samples[k], b = samples[k + 1]
        let f = (t - a.t) / max(b.t - a.t, 0.0001)
        return NSPoint(x: (a.x + (b.x - a.x) * f) * sx, y: (a.y + (b.y - a.y) * f) * sy)
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
