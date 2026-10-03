import AVFoundation
import Combine
import Speech

@MainActor
final class VoiceInputManager: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start(localeIdentifier: String) async throws {
        stop()
        transcript = ""
        errorMessage = nil

        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else {
            throw VoiceInputError.permissionDenied("Permite el reconocimiento de voz en Ajustes para dictar.")
        }

        let microphoneAuthorized = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphoneAuthorized else {
            throw VoiceInputError.permissionDenied("Permite el acceso al micrófono en Ajustes para dictar.")
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            throw VoiceInputError.unavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text { self.transcript = text }
                if error != nil || isFinal {
                    self.finishCapture()
                    self.recognitionTask = nil
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            finishCapture()
            recognitionTask?.cancel()
            recognitionTask = nil
            throw error
        }
    }

    func stop() {
        guard isRecording || recognitionTask != nil else { return }
        finishCapture()
        recognitionTask?.finish()
    }

    private func finishCapture() {
        if audioEngine.isRunning { audioEngine.stop() }
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false
    }
}

private enum VoiceInputError: LocalizedError {
    case permissionDenied(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message): message
        case .unavailable: "El reconocimiento de voz no está disponible en este momento."
        }
    }
}