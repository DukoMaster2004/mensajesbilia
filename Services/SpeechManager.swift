import Foundation
import AVFoundation
import Combine

// MARK: - Speech Manager
@MainActor
final class SpeechManager: NSObject, ObservableObject {

    static let shared = SpeechManager()

    // Wrapped in a nonisolated container to avoid Sendable warning on AVSpeechSynthesizer
    private let synthesizer: AVSpeechSynthesizer

    @Published var isPlaying: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentParagraphIndex: Int = -1
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    private var paragraphs: [String] = []
    private var language: String = "es-MX"

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    func speak(paragraphs: [String], language: String, startingAt index: Int = 0) {
        stop()
        self.paragraphs = paragraphs
        self.language = voiceLanguage(for: language)
        speakFrom(index: index)
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        isPlaying = false
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
        isPlaying = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        currentParagraphIndex = -1
    }

    func skipToNext() {
        let next = currentParagraphIndex + 1
        guard next < paragraphs.count else { stop(); return }
        synthesizer.stopSpeaking(at: .immediate)
        speakFrom(index: next)
    }

    func skipToPrevious() {
        let prev = max(0, currentParagraphIndex - 1)
        synthesizer.stopSpeaking(at: .immediate)
        speakFrom(index: prev)
    }

    // MARK: - Private

    private func speakFrom(index: Int) {
        guard index < paragraphs.count else { stop(); return }

        // Configure audio session for playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        currentParagraphIndex = index
        isPlaying = true
        isPaused = false

        let utterance = AVSpeechUtterance(string: paragraphs[index])
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.3

        synthesizer.speak(utterance)
    }

    private func voiceLanguage(for sermonLanguage: String) -> String {
        let lang = sermonLanguage.lowercased()
        if lang.contains("español") || lang.contains("spanish") || lang.contains("es") {
            return "es-MX"
        }
        return "en-US"
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let next = self.currentParagraphIndex + 1
            if next < self.paragraphs.count {
                self.speakFrom(index: next)
            } else {
                self.stop()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        // Leer isSpeaking de forma síncrona para no capturar `synthesizer`
        // (no Sendable) dentro de la closure @Sendable del Task.
        let stillSpeaking = synthesizer.isSpeaking
        Task { @MainActor in
            // Solo limpiar si no fue una transición interna (skipTo*)
            if !stillSpeaking {
                self.isPlaying = false
                self.isPaused = false
            }
        }
    }
}
