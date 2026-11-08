import AppKit
import AVFoundation
import Speech

/// Listens with Apple's speech recogniser for "Fingertip, <command>".
/// Nothing happens without the wake word, so ordinary talking during a demo
/// is ignored. A command fires once the words after the wake word have been
/// stable for a moment (or the result is final), so "spotlight off" is not
/// cut short at "spotlight", then the task restarts with a clean buffer.
/// ponytail: Apple Speech instead of a bundled Whisper; swap only if its
/// on-device model proves too slow or inaccurate for these phrases.
final class VoiceControl {
    enum Command: Equatable {
        case pointer(Bool), tap, spotlight(Bool), laser, hand, clear
        case record(Bool), replay, point(String), stopListening
    }

    var onCommand: ((Command) -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var isListening = false

    /// How long the transcript must stay unchanged before a command fires.
    static let settle: TimeInterval = 0.7

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Bumped whenever a session ends, so late callbacks and retries from it are ignored.
    private var generation = 0
    private var pending: DispatchWorkItem?
    private var sessionStart = Date()
    private var quickFailures = 0

    func start() {
        guard !isListening else { return }
        authorize { [weak self] ok in
            guard let self, ok, !self.isListening else {
                if !ok { NSLog("Fingertip: speech or microphone permission denied") }
                return
            }
            self.isListening = true
            self.quickFailures = 0
            self.beginSession()
            self.onStateChange?()
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        endSession()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        onStateChange?()
    }

    // MARK: Parsing (pure; see the self-check)

    private static let wakeWords: [[String]] = [["fingertip"], ["fingertips"], ["finger", "tip"], ["finger", "tips"]]
    private static let filler: Set<String> = ["please", "now", "okay", "ok"]
    private static let phrases: [String: Command] = [
        "tap": .tap, "click": .tap, "press": .tap,
        "spotlight": .spotlight(true), "spotlight on": .spotlight(true), "spotlight off": .spotlight(false),
        "laser": .laser, "hand": .hand,
        "clear": .clear, "erase": .clear,
        "record": .record(true), "start recording": .record(true), "stop recording": .record(false),
        "replay": .replay, "play back": .replay, "play it back": .replay,
        "pointer on": .pointer(true), "show pointer": .pointer(true), "show": .pointer(true),
        "pointer off": .pointer(false), "hide pointer": .pointer(false), "hide": .pointer(false),
        "stop listening": .stopListening, "voice off": .stopListening,
    ]

    /// The command spoken after the LAST wake word, if the words after it are
    /// exactly one command (filler like "please" ignored). Whole words only.
    static func parse(_ text: String) -> Command? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard let wakeEnd = lastWakeEnd(in: words) else { return nil }
        let rest = words[wakeEnd...].filter { !filler.contains($0) }
        guard let first = rest.first else { return nil }

        // "point at save", "point to the new tab button". Checked first so a
        // target named like a command ("point at record") still points.
        if first == "point" || first == "pointing" {
            guard rest.count >= 3, ["at", "to", "on"].contains(rest[1]) else { return nil }
            let target = rest.dropFirst(2).filter { !["the", "a", "an", "button"].contains($0) }.joined(separator: " ")
            return target.count >= 2 ? .point(target) : nil
        }
        return phrases[rest.joined(separator: " ")]
    }

    private static func lastWakeEnd(in words: [String]) -> Int? {
        var i = words.count - 1
        while i >= 0 {
            for w in wakeWords where words[i...].starts(with: w) { return i + w.count }
            i -= 1
        }
        return nil
    }

    // MARK: Session

    private func authorize(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { DispatchQueue.main.async { done(false) }; return }
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
        }
    }

    private func beginSession() {
        guard isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            NSLog("Fingertip: speech recogniser unavailable; voice off")
            stop()
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // On-device needs the en-US dictation model downloaded; otherwise Apple's server is used.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.contextualStrings = ["Fingertip", "spotlight", "laser", "replay", "point at"]
        req.addsPunctuation = false
        request = req

        if !engine.isRunning {
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            engine.prepare()
            do { try engine.start() } catch {
                NSLog("Fingertip: audio engine failed: \(error); voice off")
                stop()
                return
            }
        }

        generation += 1
        let gen = generation
        sessionStart = Date()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async { self?.handle(result: result, error: error, gen: gen) }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, gen: Int) {
        guard isListening, gen == generation else { return }
        pending?.cancel(); pending = nil
        let cmd = result.flatMap { Self.parse($0.bestTranscription.formattedString) }

        if error != nil || result?.isFinal == true {
            if let cmd { fire(cmd); return }
            // Apple ends a task on long silence or after ~1 min: just start another.
            // A task that fails within 2 s is a real failure (dictation off, no
            // model, no network): back off, and give up after a few in a row.
            let quick = error != nil && Date().timeIntervalSince(sessionStart) < 2
            quickFailures = quick ? quickFailures + 1 : 0
            if quickFailures >= 5 {
                NSLog("Fingertip: speech recognition keeps failing (%@); voice off", "\(error.map { "\($0)" } ?? "?")")
                stop()
                return
            }
            let delay = quick ? 0.5 * pow(2, Double(quickFailures - 1)) : 0
            endSession()
            let g = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == g else { return }
                self.beginSession()
            }
            return
        }

        guard let cmd else { return }
        // Wait for the phrase to settle: "spotlight" may still become "spotlight off".
        let work = DispatchWorkItem { [weak self] in self?.fire(cmd) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }

    private func fire(_ cmd: Command) {
        endSession()
        quickFailures = 0
        onCommand?(cmd)
        if isListening { beginSession() }  // clean buffer for the next phrase
    }

    private func endSession() {
        pending?.cancel(); pending = nil
        generation += 1
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
    }
}
