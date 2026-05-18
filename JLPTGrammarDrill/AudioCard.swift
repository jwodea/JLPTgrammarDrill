import Foundation
import SwiftData
import SwiftFSRS

/// FSRS-tracked state for a single exercise inside the audio drill.
/// Mirrors the field layout used by `SRSRecord` so the same scheduler can be reused.
@Model
final class AudioCard {
    @Attribute(.unique) var exerciseId: String

    // FSRS card state — mirrors SRSRecord exactly.
    var fsrsDue: Date
    var fsrsStability: Double
    var fsrsDifficulty: Double
    var fsrsElapsedDays: Double
    var fsrsScheduledDays: Double
    var fsrsReps: Int
    var fsrsLapses: Int
    var fsrsStatusRaw: Int  // 0 new, 1 learning, 2 review, 3 relearning
    var fsrsLastReview: Date?

    /// When this card was first introduced into the active learning pool.
    /// Used to enforce the daily new-card budget (Ringotan-style introduction pacing).
    var introducedAt: Date?

    init(exerciseId: String) {
        self.exerciseId = exerciseId
        let newCard = Card()
        self.fsrsDue = newCard.due
        self.fsrsStability = newCard.stability
        self.fsrsDifficulty = newCard.difficulty
        self.fsrsElapsedDays = newCard.elapsedDays
        self.fsrsScheduledDays = newCard.scheduledDays
        self.fsrsReps = newCard.reps
        self.fsrsLapses = newCard.lapses
        self.fsrsStatusRaw = 0
        self.fsrsLastReview = newCard.lastReview
        self.introducedAt = nil
    }

    /// Reconstruct a SwiftFSRS Card from stored fields.
    var fsrsCard: Card {
        var card = Card()
        card.due = fsrsDue
        card.stability = fsrsStability
        card.difficulty = fsrsDifficulty
        card.elapsedDays = fsrsElapsedDays
        card.scheduledDays = fsrsScheduledDays
        card.reps = fsrsReps
        card.lapses = fsrsLapses
        card.lastReview = fsrsLastReview
        switch fsrsStatusRaw {
        case 0: card.status = .new
        case 1: card.status = .learning
        case 2: card.status = .review
        case 3: card.status = .relearning
        default: card.status = .new
        }
        return card
    }

    /// Apply a SwiftFSRS Card returned by the scheduler.
    func update(from card: Card) {
        self.fsrsDue = card.due
        self.fsrsStability = card.stability
        self.fsrsDifficulty = card.difficulty
        self.fsrsElapsedDays = card.elapsedDays
        self.fsrsScheduledDays = card.scheduledDays
        self.fsrsReps = card.reps
        self.fsrsLapses = card.lapses
        self.fsrsLastReview = card.lastReview
        switch card.status {
        case .new: self.fsrsStatusRaw = 0
        case .learning: self.fsrsStatusRaw = 1
        case .review: self.fsrsStatusRaw = 2
        case .relearning: self.fsrsStatusRaw = 3
        }
    }

    var isInLearningPool: Bool {
        fsrsStatusRaw == 1 || fsrsStatusRaw == 3
    }
}
