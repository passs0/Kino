import Foundation
import Combine
import Speech
import AVFoundation
import Translation

/// Language option for live recognition and translation.
public struct LiveLanguageOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let flag: String
    public let speechLocale: String
    public let translationCode: String

    public init(id: String, name: String, flag: String, speechLocale: String, translationCode: String) {
        self.id = id
        self.name = name
        self.flag = flag
        self.speechLocale = speechLocale
        self.translationCode = translationCode
    }
}

/// Central manager orchestrating real-time on-device speech-to-text and neural translation.
@MainActor
public final class LiveCaptionManager: ObservableObject {
    public static let shared = LiveCaptionManager()

    // MARK: - Supported Language Catalogs

    public static let availableSourceLanguages: [LiveLanguageOption] = [
        LiveLanguageOption(id: "ja-JP", name: "Japanese (日本語)", flag: "🇯🇵", speechLocale: "ja-JP", translationCode: "ja"),
        LiveLanguageOption(id: "en-US", name: "English (US)", flag: "🇺🇸", speechLocale: "en-US", translationCode: "en"),
        LiveLanguageOption(id: "ko-KR", name: "Korean (한국어)", flag: "🇰🇷", speechLocale: "ko-KR", translationCode: "ko"),
        LiveLanguageOption(id: "zh-TW", name: "Mandarin (繁體中文)", flag: "🇹🇼", speechLocale: "zh-TW", translationCode: "zh-Hant"),
        LiveLanguageOption(id: "zh-CN", name: "Mandarin (简体中文)", flag: "🇨🇳", speechLocale: "zh-CN", translationCode: "zh-Hans"),
        LiveLanguageOption(id: "fr-FR", name: "French (Français)", flag: "🇫🇷", speechLocale: "fr-FR", translationCode: "fr"),
        LiveLanguageOption(id: "de-DE", name: "German (Deutsch)", flag: "🇩🇪", speechLocale: "de-DE", translationCode: "de"),
        LiveLanguageOption(id: "es-ES", name: "Spanish (Español)", flag: "🇪🇸", speechLocale: "es-ES", translationCode: "es")
    ]

    public static let availableTargetLanguages: [LiveLanguageOption] = [
        LiveLanguageOption(id: "zh-Hant", name: "Traditional Chinese (繁體中文)", flag: "🇹🇼", speechLocale: "zh-TW", translationCode: "zh-Hant"),
        LiveLanguageOption(id: "en", name: "English", flag: "🇺🇸", speechLocale: "en-US", translationCode: "en"),
        LiveLanguageOption(id: "zh-Hans", name: "Simplified Chinese (简体中文)", flag: "🇨🇳", speechLocale: "zh-CN", translationCode: "zh-Hans"),
        LiveLanguageOption(id: "ja", name: "Japanese (日本語)", flag: "🇯🇵", speechLocale: "ja-JP", translationCode: "ja"),
        LiveLanguageOption(id: "ko", name: "Korean (한국어)", flag: "🇰🇷", speechLocale: "ko-KR", translationCode: "ko"),
        LiveLanguageOption(id: "none", name: "Verbatim Speech (No Translation)", flag: "🎙️", speechLocale: "", translationCode: "none")
    ]

    // MARK: - Published State

    @Published public var isEnabled: Bool = false
    @Published public var isCapturing: Bool = false
    @Published public var selectedSourceID: String = "ja-JP" {
        didSet { updateConfiguration() }
    }
    @Published public var selectedTargetID: String = "zh-Hant" {
        didSet { updateConfiguration() }
    }

    @Published public var liveTranscript: String = ""
    @Published public var liveTranslation: String = ""
    @Published public var statusNotice: String? = nil

    @Published public var translationConfig: TranslationSession.Configuration?

    // MARK: - Internal Engine References

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var activeSession: TranslationSession?
    private var audioProcess: Process?
    private var audioPipe: Pipe?
    private var audioFeedTask: Task<Void, Never>?
    private var silenceTimerTask: Task<Void, Never>?
    private var translationDebounceTask: Task<Void, Never>?

    private let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!

    private init() {
        updateConfiguration()
    }

    // MARK: - Configuration Updates

    public func updateConfiguration() {
        guard selectedTargetID != "none" else {
            translationConfig = nil
            activeSession = nil
            return
        }

        let src = Self.availableSourceLanguages.first(where: { $0.id == selectedSourceID })?.translationCode ?? "ja"
        let tgt = Self.availableTargetLanguages.first(where: { $0.id == selectedTargetID })?.translationCode ?? "zh-Hant"

        if src != tgt {
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: src),
                target: Locale.Language(identifier: tgt)
            )
        } else {
            translationConfig = nil
        }

        if isEnabled {
            restartSession()
        }
    }

    public func registerTranslationSession(_ session: TranslationSession) {
        self.activeSession = session
    }

    // MARK: - Toggles and Lifecycle

    public func toggleLiveCaptions() {
        if isEnabled {
            stopLiveCaptions()
            PlayerController.shared.showHUD(message: "Live Captions: OFF", iconName: "captions.bubble")
        } else {
            startLiveCaptions()
            let srcName = Self.availableSourceLanguages.first(where: { $0.id == selectedSourceID })?.flag ?? ""
            let tgtName = Self.availableTargetLanguages.first(where: { $0.id == selectedTargetID })?.flag ?? ""
            let label = (selectedTargetID == "none") ? "Live Captions: ON" : "Live Captions: ON (\(srcName) → \(tgtName))"
            PlayerController.shared.showHUD(message: label, iconName: "captions.bubble.fill")
        }
    }

    public func startLiveCaptions() {
        guard !isEnabled else { return }

        // Request Speech Recognition permission if needed
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard auth == .authorized else {
                    self.statusNotice = "Speech Recognition authorization required in System Settings."
                    return
                }
                self.isEnabled = true
                self.startPipeline(from: PlayerController.shared.currentTime)
            }
        }
    }

    public func stopLiveCaptions() {
        isEnabled = false
        isCapturing = false
        teardownPipeline()
        SubtitleManager.shared.setLiveCaptionText(nil)
        liveTranscript = ""
        liveTranslation = ""
    }

    public func restartSession() {
        guard isEnabled else { return }
        teardownPipeline()
        startPipeline(from: PlayerController.shared.currentTime)
    }

    // MARK: - Playback Event Hooks

    public func handleUserSeek(to timestamp: Double) {
        guard isEnabled else { return }
        teardownPipeline()
        SubtitleManager.shared.setLiveCaptionText(nil)
        startPipeline(from: timestamp)
    }

    public func handlePause() {
        guard isEnabled else { return }
        teardownPipeline()
    }

    public func handlePlay() {
        guard isEnabled else { return }
        teardownPipeline()
        startPipeline(from: PlayerController.shared.currentTime)
    }

    // MARK: - Pipeline Implementation

    private func startPipeline(from timestamp: Double) {
        guard let source = MediaCoordinator.shared.currentSource else { return }
        guard let ffmpegPath = ToolLocator.shared.path(for: "ffmpeg") else {
            statusNotice = "FFmpeg is required for audio streaming."
            return
        }

        let srcOption = Self.availableSourceLanguages.first(where: { $0.id == selectedSourceID })
        let speechLocaleID = srcOption?.speechLocale ?? "ja-JP"
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: speechLocaleID)), recognizer.isAvailable else {
            statusNotice = "Speech Recognizer unavailable for \(speechLocaleID)."
            return
        }

        self.speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self, self.isEnabled else { return }
                if let r = result {
                    let transcript = r.bestTranscription.formattedString
                    self.handleIncomingTranscript(transcript)
                }
                if let err = error {
                    // Ignore expected audio buffer flush errors during seek/pause
                    if (err as NSError).code != 203 && (err as NSError).code != 1110 {
                        print("[LiveCaption] Recognition error: \(err.localizedDescription)")
                    }
                }
            }
        }

        // Determine input media path or URL
        let inputArg: String
        switch source {
        case .local(let url):
            inputArg = url.path
        case .online(let url, _):
            inputArg = url.absoluteString
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpegPath)
        let startTimeArg = String(format: "%.3f", max(0, timestamp))
        p.arguments = [
            "-ss", startTimeArg,
            "-i", inputArg,
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-f", "s16le",
            "-"
        ]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()

        do {
            try p.run()
            self.audioProcess = p
            self.audioPipe = pipe
            self.isCapturing = true

            startAudioFeeder(pipe: pipe, request: request, process: p)
        } catch {
            print("[LiveCaption] Failed to spawn ffmpeg: \(error)")
        }
    }

    private func startAudioFeeder(pipe: Pipe, request: SFSpeechAudioBufferRecognitionRequest, process: Process) {
        audioFeedTask?.cancel()
        audioFeedTask = Task.detached(priority: .userInitiated) { [pcmFormat] in
            let handle = pipe.fileHandleForReading
            let chunkSize = 3200 // 100ms of 16kHz 16-bit mono PCM

            while !Task.isCancelled && process.isRunning {
                let data = handle.readData(ofLength: chunkSize)
                if data.isEmpty { break }

                let frameCount = UInt32(data.count / 2)
                if let pcm = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) {
                    pcm.frameLength = frameCount
                    data.withUnsafeBytes { raw in
                        if let base = raw.baseAddress {
                            memcpy(pcm.int16ChannelData![0], base, data.count)
                        }
                    }
                    request.append(pcm)
                }

                // Pace feeding in exact sync with real-time video playback (100ms chunks)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            request.endAudio()
        }
    }

    private func handleIncomingTranscript(_ transcript: String) {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        self.liveTranscript = clean

        // Schedule silence auto-fade timer (clears subtitle after 3.2s of inactivity)
        silenceTimerTask?.cancel()
        silenceTimerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            self?.liveTranscript = ""
            self?.liveTranslation = ""
            SubtitleManager.shared.setLiveCaptionText(nil)
        }

        // If no translation requested, output verbatim recognized text immediately
        if selectedTargetID == "none" {
            SubtitleManager.shared.setLiveCaptionText(clean)
            return
        }

        // Debounce neural translation requests (~200ms) to coalesce streaming partial words
        translationDebounceTask?.cancel()
        translationDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self = self else { return }

            if let session = self.activeSession {
                do {
                    let response = try await session.translate(clean)
                    let targetText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !targetText.isEmpty {
                        self.liveTranslation = targetText
                        SubtitleManager.shared.setLiveCaptionText(targetText)
                    }
                } catch {
                    // Fallback to original transcript if translation is preparing or encounters an issue
                    SubtitleManager.shared.setLiveCaptionText(clean)
                }
            } else {
                SubtitleManager.shared.setLiveCaptionText(clean)
            }
        }
    }

    private func teardownPipeline() {
        audioFeedTask?.cancel()
        audioFeedTask = nil

        silenceTimerTask?.cancel()
        silenceTimerTask = nil

        translationDebounceTask?.cancel()
        translationDebounceTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        if let p = audioProcess, p.isRunning {
            p.terminate()
        }
        audioProcess = nil
        audioPipe = nil
        isCapturing = false
    }
}
