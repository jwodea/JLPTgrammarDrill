import Foundation
import AVFoundation

/// Plays a Japanese sentence aloud using on-device TTS, at a slow learner-friendly pace.
@MainActor
final class JapaneseSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    // Pending activate-then-speak work; cancelled by `stop()` or a newer `speak` call.
    private var speakTask: Task<Void, Never>?

    /// Speak `text` in Japanese. Defaults to a slow rate suitable for learners.
    func speak(_ text: String, rate: Float = 0.42) {
        guard !text.isEmpty else { return }
        speakTask?.cancel()
        synthesizer.stopSpeaking(at: .immediate)

        // Switch the audio session into playback so the system mic capture doesn't suppress output.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.selectedVoice()
        utterance.rate = rate
        utterance.preUtteranceDelay = 0.1

        // Activate asynchronously: synchronous `setActive` on the main thread can hang the UI.
        speakTask = Task { [synthesizer] in
            if #available(iOS 27.0, *) {
                _ = try? await session.activate()
            } else {
                await Task.detached {
                    try? AVAudioSession.sharedInstance().setActive(true, options: [])
                }.value
            }
            guard !Task.isCancelled else { return }
            synthesizer.speak(utterance)
        }
    }

    /// Resolve the user's chosen Japanese voice, falling back to the system default.
    static func selectedVoice() -> AVSpeechSynthesisVoice? {
        let id = UserDefaults.standard.string(forKey: AudioDrillSettings.voiceIdentifierKey) ?? ""
        if !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        return AVSpeechSynthesisVoice(language: "ja-JP")
    }

    /// Installed Japanese voices worth offering: Enhanced or Premium only. The compact
    /// (default-quality) voices sound noticeably worse than the system default, so we hide
    /// them; users who want better voices can download them from
    /// Settings → Accessibility → Spoken Content → Voices → Japanese.
    static func availableJapaneseVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ja") }
            .filter { $0.quality == .enhanced || $0.quality == .premium }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
}
