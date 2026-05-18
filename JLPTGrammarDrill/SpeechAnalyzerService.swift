import Foundation

/// Stub for the iOS 26+ `SpeechAnalyzer`-based recognizer.
/// Not wired up yet — a future PR can replace `SFSpeechRecognitionService` here
/// without touching any view code.
@available(iOS 26.0, *)
@MainActor
final class SpeechAnalyzerService: SpeechRecognitionService {
    func requestAuthorization() async -> Bool {
        fatalError("SpeechAnalyzerService not yet implemented")
    }

    func startRecording() async throws {
        fatalError("SpeechAnalyzerService not yet implemented")
    }

    func stopRecordingAndTranscribe() async throws -> SpeechTranscription {
        fatalError("SpeechAnalyzerService not yet implemented")
    }

    func cancel() {
        fatalError("SpeechAnalyzerService not yet implemented")
    }
}
