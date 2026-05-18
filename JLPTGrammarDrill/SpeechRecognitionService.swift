import Foundation

/// One transcribed recording produced by a `SpeechRecognitionService`.
struct SpeechTranscription: Sendable {
    let raw: String
    let durationMs: Int
}

/// Errors emitted by speech recognition services.
enum SpeechRecognitionError: LocalizedError {
    case permissionDenied
    case onDeviceUnavailable
    case recognizerUnavailable
    case audioSessionFailure(String)
    case recognitionFailed(String)
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or speech recognition permission was denied. Enable it in Settings."
        case .onDeviceUnavailable:
            return "On-device Japanese recognition is unavailable. Enable Japanese dictation in Settings → General → Keyboard → Dictation."
        case .recognizerUnavailable:
            return "The Japanese speech recognizer is currently unavailable."
        case .audioSessionFailure(let detail):
            return "Audio session error: \(detail)"
        case .recognitionFailed(let detail):
            return "Speech recognition failed: \(detail)"
        case .noSpeechDetected:
            return "No speech was detected."
        }
    }
}

/// Abstract on-device speech recognizer. SFSpeechRecognizer-backed for v1;
/// SpeechAnalyzer-backed for iOS 26+ can replace this without view changes.
@MainActor
protocol SpeechRecognitionService: AnyObject {
    /// Request all required permissions (mic + speech). Returns `true` if both granted.
    func requestAuthorization() async -> Bool

    /// Begin capturing microphone audio and feeding it to the recognizer.
    func startRecording() async throws

    /// Stop capturing audio and return the final transcription.
    /// If already stopped, this throws.
    func stopRecordingAndTranscribe() async throws -> SpeechTranscription

    /// Abort an in-flight recording without waiting for a final transcript.
    /// Tears down the audio engine, recognition task, and audio session.
    /// Safe to call when not recording (no-op).
    func cancel()
}
