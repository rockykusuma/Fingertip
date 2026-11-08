import AppKit

/// A short stadium cheer for the foam finger, synthesised once at first use:
/// band-limited noise under a swell (the roar), scattered hand claps, and a
/// few rising "woo" whistles, written to an in-memory 16-bit WAV.
/// ponytail: synthetic crowd; drop a recorded cheer.wav in Resources and
/// load it here if this ever sounds cheap.
enum CheerSound {
    private static let sound: NSSound? = {
        let s = NSSound(data: synthesize())
        s?.volume = 0.6
        return s
    }()

    static func play() {
        guard Prefs.playTapSound, let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    static let sampleRate = 22_050.0
    static let duration = 1.6

    /// Deterministic so every cheer sounds the same.
    private struct LCG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    static func synthesize() -> Data {
        let rate = sampleRate
        let n = Int(rate * duration)
        var out = [Float](repeating: 0, count: n)
        var rng = LCG(state: 0xF00D_F1A6)

        // Roar: white noise through a 250 Hz–1.2 kHz band (difference of two
        // one-pole low-passes), fast swell then a slow fall.
        var lpHigh: Float = 0, lpLow: Float = 0
        let aHigh = Float(1 - exp(-2 * .pi * 1200 / rate)), aLow = Float(1 - exp(-2 * .pi * 250 / rate))
        for i in 0..<n {
            let t = Double(i) / rate
            let env = Float(min(t / 0.12, 1) * exp(-max(0, t - 0.35) * 2.2))
            let w = Float.random(in: -1...1, using: &rng)
            lpHigh += aHigh * (w - lpHigh)
            lpLow += aLow * (w - lpLow)
            out[i] = (lpHigh - lpLow) * 2.2 * env
        }

        // Claps: short bright noise bursts with a fast decay.
        let clapLen = Int(0.012 * rate)
        for _ in 0..<70 {
            let start = Int(Double.random(in: 0.02...1.1, using: &rng) * rate)
            let gain = Float.random(in: 0.15...0.35, using: &rng)
            for k in 0..<clapLen where start + k < n {
                out[start + k] += Float.random(in: -1...1, using: &rng) * gain * Float(exp(-Double(k) / (0.003 * rate)))
            }
        }

        // Whoos: rising sine glides with a little vibrato, faded in and out.
        for _ in 0..<3 {
            let start = Double.random(in: 0.05...0.4, using: &rng)
            let len = Double.random(in: 0.5...0.9, using: &rng)
            let f0 = Double.random(in: 450...650, using: &rng)
            let f1 = f0 * Double.random(in: 1.4...1.8, using: &rng)
            var phase = 0.0
            let count = Int(len * rate)
            for k in 0..<count {
                let i = Int(start * rate) + k
                guard i < n else { break }
                let u = Double(k) / Double(count)
                let f = f0 + (f1 - f0) * min(u * 1.6, 1) + 12 * sin(2 * .pi * 6 * Double(k) / rate)
                phase += 2 * .pi * f / rate
                out[i] += Float(sin(phase) * sin(.pi * u) * 0.09)
            }
        }

        let peak = out.lazy.map(abs).max() ?? 0
        let gain: Float = peak > 0 ? 0.8 / peak : 1

        var data = Data(capacity: 44 + n * 2)
        func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + n * 2)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        ascii("data"); u32(UInt32(n * 2))
        for s in out {
            u16(UInt16(bitPattern: Int16(max(-1, min(1, s * gain)) * 32_767)))
        }
        return data
    }
}
