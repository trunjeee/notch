import AppKit
import AVFoundation
import Speech

/// Hold-to-talk dictation driven by VoiceInputTrigger: right Option down
/// starts recording, up finishes it and types the transcript into the
/// focused field via TextInjector.
///
/// Recognition is strictly on-device (`requiresOnDeviceRecognition`): no
/// audio ever leaves the Mac, and if the active locale can't be recognized
/// locally, dictation refuses to run rather than falling back to Apple's
/// servers. The locale follows the keyboard layout in use at the moment of
/// the press — Russian layout dictates Russian, Latin dictates English.
@MainActor
final class DictationController {

    private let indicator = DictationIndicator()
    private let inputSources = InputSourceManager()

    /// Set by `begin`, cleared by `end`. Guards re-entry and tells a late
    /// permission callback the key was already released.
    private var active = false

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    /// The recognizer works in utterance segments: at a pause it silently
    /// drops its partial text and starts a fresh segment. Segments it has
    /// finished (or tried to finish without telling anyone) are banked here,
    /// or a long dictation would insert only its tail.
    private var finalizedText = ""
    /// The current, still-rewritable segment.
    private var latestPartial = ""
    /// Set by `stopRecordingAndFinalize`: the key is up, the audio stream is
    /// closed, and the next final result is the closing one.
    private var finishing = false

    private var fullText: String {
        [finalizedText, latestPartial]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func appendFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        finalizedText = finalizedText.isEmpty ? trimmed : finalizedText + " " + trimmed
        latestPartial = ""
    }

    /// Safety net while waiting for the final recognition result after the
    /// key comes up — see `stopRecordingAndFinalize`.
    private var finalizeWorkItem: DispatchWorkItem?
    /// Hard cap on a session, in case someone leans on the key.
    private var maxSessionTimer: Timer?

    /// Audio-thread metering state — only ever touched on the tap's
    /// real-time thread, so the unchecked sendability is contained.
    nonisolated(unsafe) private var lastLevelPush: CFAbsoluteTime = 0

    // MARK: - Trigger events

    /// Wired to the notch panel: recording on/off and the live mic level.
    var onStateChange: ((Bool) -> Void)?
    var onLevel: ((Float) -> Void)?

    /// Right Option went down.
    func begin() {
        guard !active else { return }
        active = true
        NSLog("notchbytrj-dictation: begin")
        ensurePermissions { [weak self] granted in
            guard let self, self.active else { return }
            guard granted else {
                self.active = false
                NSLog("notchbytrj-dictation: microphone or speech recognition permission denied")
                NSSound.beep()
                return
            }
            self.startRecording()
        }
    }

    /// Right Option came up.
    func end() {
        guard active else { return }
        active = false
        // engine == nil means the press was shorter than the permission
        // round-trip: nothing was ever recorded, nothing to finish. The
        // pending callback will see `active == false` and bail out.
        if engine != nil {
            stopRecordingAndFinalize()
        }
    }

    /// For app termination: drop everything, insert nothing.
    func cancel() {
        active = false
        task?.cancel()
        cleanup(inserting: "")
    }

    // MARK: - Permissions

    /// Both prompts fire lazily here — on the first key press — never at
    /// launch, matching how every other permission in the app behaves.
    private func ensurePermissions(_ done: @escaping @MainActor (Bool) -> Void) {
        func speechOK(_ completion: @escaping @MainActor (Bool) -> Void) {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                completion(true)
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { status in
                    Task { @MainActor in completion(status == .authorized) }
                }
            default:
                completion(false)
            }
        }
        func micOK(_ completion: @escaping @MainActor (Bool) -> Void) {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                completion(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in completion(granted) }
                }
            default:
                completion(false)
            }
        }
        speechOK { speech in micOK { mic in done(speech && mic) } }
    }

    // MARK: - Recording

    private func startRecording() {
        finalizedText = ""
        latestPartial = ""
        finishing = false

        let language = inputSources.currentLanguage()
        let localeID = (language == .russian) ? "ru-RU" : "en-US"

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)),
              recognizer.isAvailable else {
            NSLog("notchbytrj-dictation: no recognizer for \(localeID)")
            active = false
            NSSound.beep()
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            NSLog("notchbytrj-dictation: \(localeID) can't be recognized on-device — refusing to send audio out")
            active = false
            NSSound.beep()
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        self.request = request

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.pushLevel(of: buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.appendFinal(text)
                        if self.finishing {
                            self.cleanup(inserting: self.fullText)
                            return
                        }
                    } else {
                        // Silent segment reset: on a pause the recognizer
                        // abandons the partial text it had been building and
                        // starts the next utterance from scratch. A partial
                        // that the new text doesn't continue was finalized
                        // without anyone saying so — bank it before it's gone.
                        if !self.latestPartial.isEmpty {
                            let common = text.commonPrefix(with: self.latestPartial)
                            if common.count < self.latestPartial.count / 2 {
                                self.appendFinal(self.latestPartial)
                            }
                        }
                        self.latestPartial = text
                    }
                }
                if let error {
                    let nsError = error as NSError
                    // A cancel we asked for ourselves is not an error.
                    let isSelfCancel = nsError.code == NSUserCancelledError
                        || (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216)
                    if !isSelfCancel {
                        NSLog("notchbytrj-dictation: recognition error: \(error.localizedDescription)")
                    }
                    self.cleanup(inserting: self.fullText)
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("notchbytrj-dictation: audio engine failed to start: \(error.localizedDescription)")
            cleanup(inserting: "")
            NSSound.beep()
            return
        }
        self.engine = engine

        indicator.show()
        onStateChange?(true)
        SwitchSound.play()
        NSLog("notchbytrj-dictation: recording started (\(localeID), on-device)")

        maxSessionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.end() }
        }
    }

    /// The key is up: close the audio stream and wait for the final result,
    /// which usually lands well under a second. If the recognizer never
    /// sends one, the timer inserts whatever text has been banked so far.
    private func stopRecordingAndFinalize() {
        finishing = true
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cleanup(inserting: self.fullText)
        }
        finalizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func cleanup(inserting text: String) {
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil
        maxSessionTimer?.invalidate()
        maxSessionTimer = nil

        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil

        indicator.hide()
        onStateChange?(false)

        active = false
        finishing = false
        finalizedText = ""
        latestPartial = ""

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            TextInjector.insert(trimmed)
            SwitchSound.play()
        }
    }

    // MARK: - Level metering

    /// Runs on the audio tap's real-time thread: keep it cheap, and hand
    /// off to the UI no more than ~10 times a second.
    nonisolated private func pushLevel(of buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var peak: Float = 0
        for i in 0..<count {
            let value = abs(channel[i])
            if value > peak { peak = value }
        }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLevelPush > 0.08 else { return }
        lastLevelPush = now
        let level = min(1, peak * 4.5)
        DispatchQueue.main.async { [weak self] in
            self?.indicator.update(level: level)
            self?.onLevel?(level)
        }
    }
}
