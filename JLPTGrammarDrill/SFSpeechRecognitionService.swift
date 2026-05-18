import Foundation
import Speech
import AVFoundation

/// On-device Japanese speech recognizer backed by `SFSpeechRecognizer` + `AVAudioEngine`.
@MainActor
final class SFSpeechRecognitionService: SpeechRecognitionService {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var lastTranscription: String = ""
    private var recordingStart: Date?
    private var isRecording = false

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    }

    func requestAuthorization() async -> Bool {
        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else { return false }
        let mic = await Self.requestMicrophoneAccess()
        return mic
    }

    func startRecording() async throws {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechRecognitionError.onDeviceUnavailable
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechRecognitionError.permissionDenied
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognitionError.audioSessionFailure(error.localizedDescription)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            request.addsPunctuation = false
        }
        self.request = request
        self.lastTranscription = ""
        self.recordingStart = Date()

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.lastTranscription = result.bestTranscription.formattedString
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechRecognitionError.audioSessionFailure(error.localizedDescription)
        }
        isRecording = true
    }

    func stopRecordingAndTranscribe() async throws -> SpeechTranscription {
        guard isRecording else {
            throw SpeechRecognitionError.recognitionFailed("Not currently recording.")
        }
        isRecording = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

        // Give the recognizer a brief moment to flush its final result.
        let deadline = Date().addingTimeInterval(2.0)
        while task?.state != .completed && Date() < deadline {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        let durationMs: Int
        if let start = recordingStart {
            durationMs = Int(Date().timeIntervalSince(start) * 1000)
        } else {
            durationMs = 0
        }

        let finalText = lastTranscription
        task?.cancel()
        task = nil
        request = nil
        recordingStart = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if finalText.isEmpty {
            return SpeechTranscription(raw: "", durationMs: durationMs)
        }
        return SpeechTranscription(raw: finalText, durationMs: durationMs)
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recordingStart = nil
        lastTranscription = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Authorization helpers

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
