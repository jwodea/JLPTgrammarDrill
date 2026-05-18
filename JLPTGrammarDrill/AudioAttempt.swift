import Foundation
import SwiftData

/// One recorded (or synthetic) audio attempt for an exercise. Kept forever for review.
@Model
final class AudioAttempt {
    @Attribute(.unique) var id: UUID
    var exerciseId: String
    var timestamp: Date

    var rawTranscription: String              // exact recognizer output, or "<marked too easy>"
    var normalizedTranscription: String       // after TextNormalizer
    var bestMatchKanji: String?
    var matchScore: Double                    // 0.0–1.0; 1.0 for synthetic "too easy"
    var thresholdUsed: Double                 // threshold at the time of the attempt
    var stripFinalCopulaUsed: Bool
    var passed: Bool
    var fsrsGrade: Int?                       // 1 Again, 2 Hard, 3 Good, 4 Easy; nil until graded
    var durationMs: Int                       // 0 for synthetic attempts
    var synthetic: Bool                       // true when produced by "too easy"

    init(exerciseId: String,
         rawTranscription: String,
         normalizedTranscription: String,
         bestMatchKanji: String?,
         matchScore: Double,
         thresholdUsed: Double,
         stripFinalCopulaUsed: Bool,
         passed: Bool,
         durationMs: Int,
         synthetic: Bool = false,
         fsrsGrade: Int? = nil) {
        self.id = UUID()
        self.exerciseId = exerciseId
        self.timestamp = .now
        self.rawTranscription = rawTranscription
        self.normalizedTranscription = normalizedTranscription
        self.bestMatchKanji = bestMatchKanji
        self.matchScore = matchScore
        self.thresholdUsed = thresholdUsed
        self.stripFinalCopulaUsed = stripFinalCopulaUsed
        self.passed = passed
        self.fsrsGrade = fsrsGrade
        self.durationMs = durationMs
        self.synthetic = synthetic
    }
}
