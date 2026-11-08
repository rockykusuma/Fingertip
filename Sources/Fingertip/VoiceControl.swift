import AppKit
import AVFoundation
import Speech

/// Listens continuously with Apple's on-device speech recogniser and turns
/// short phrases into commands. Each recognised command restarts the
/// recognition task so the transcript buffer starts clean.
/// ponytail: Apple Speech instead of a bundled Whisper; swap only if its
/// on-device model proves too slow or inaccurate for these ~12 phrases.
final class VoiceControl {
    enum Command: Equatable {
        case pointer(Bool), tap, spotlight(Bool), laser, hand, clear
        case record(Bool), replay, point(String), stopListening
    }

    var onCommand: ((Command) -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var isListening = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0

    func start() {
        guard !isListening else { return }
        authorize { [weak self] ok in
            guard let self, ok else { NSLog("Fingertip: speech or microphone permission denied"); return }
            self.isListening = true
            self.beginSession()
            self.onStateChange?()
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        generation += 1
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        onStateChange?()
    }

    // MARK: Parsing (pure; see `parse`)

    /// The command at the END of a lowercase transcript, if any. The buffer
    /// accumulates until a command fires, so only the tail matters.
    static func parse(_ text: String) -> Command? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let tail = words.suffix(3).joined(separator: " ")
        func ends(_ phrases: String...) -> Bool { phrases.contains { tail.hasSuffix($0) } }

        if ends("stop recording", "stop record") { return .record(false) }
        if ends("stop listening", "voice off") { return .stopListening }
        if ends("start recording", "record") { return .record(true) }
        if ends("spotlight on", "spotlight") { return .spotlight(true) }
        if ends("spotlight off") { return .spotlight(false) }
        if ends("pointer off", "hide pointer", "hide hand") { return .pointer(false) }
        if ends("pointer on", "show pointer", "show hand") { return .pointer(true) }
        if ends("laser") { return .laser }
        if ends("hand") { return .hand }
        if ends("clear", "erase") { return .clear }
        if ends("tap", "click", "press") { return .tap }
        if ends("replay", "play it back", "play back") { return .replay }

        // "point at save", "point to the new tab" — target is everything after at/to.
        if let i = words.lastIndex(where: { $0 == "point" }), i + 2 < words.count,
           ["at", "to", "on"].contains(words[i + 1]) {
            let target = words[(i + 2)...].filter { !["the", "a", "an", "button"].contains($0) }.joined(separator: " ")
            if target.count >= 2 { return .point(target) }
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
        guard isListening, let recognizer, recognizer.isAvailable else {
            NSLog("Fingertip: speech recogniser unavailable"); return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // On-device needs the en-US dictation model downloaded; otherwise Apple's server is used.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.contextualStrings = ["tap", "spotlight", "laser", "hand", "replay", "point at", "clear", "record"]
        if #available(macOS 13, *) { req.addsPunctuation = false }
        request = req

        if !engine.isRunning {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            engine.prepare()
            do { try engine.start() } catch { NSLog("Fingertip: audio engine failed: \(error)"); return }
        }

        generation += 1
        let gen = generation
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isListening, gen == self.generation else { return }
                if let result, let cmd = Self.parse(result.bestTranscription.formattedString) {
                    self.onCommand?(cmd)
                    self.restart()
                    return
                }
                // Apple ends a task after ~1 min or on silence; just start another.
                if error != nil || result?.isFinal == true { self.restart() }
            }
        }
    }

    private func restart() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        beginSession()
    }
}
