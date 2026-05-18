import Foundation
import SwiftData
import SwiftFSRS

@Model
final class SRSRecord {
    // Links to a GrammarPoint by its string id
    @Attribute(.unique) var grammarId: String

    // FSRS card state — stored as individual fields since Card is a value type
    var fsrsDue: Date
    var fsrsStability: Double
    var fsrsDifficulty: Double
    var fsrsElapsedDays: Double
    var fsrsScheduledDays: Double
    var fsrsReps: Int
    var fsrsLapses: Int
    var fsrsStatusRaw: Int  // maps to SwiftFSRS.Status: .new=0, .learning=1, .review=2, .relearning=3
    var fsrsLastReview: Date?

    // App-level tracking
    var totalCorrect: Int = 0
    var totalAttempts: Int = 0
    var lastStudied: Date?

    init(grammarId: String) {
        self.grammarId = grammarId
        let newCard = Card()
        self.fsrsDue = newCard.due
        self.fsrsStability = newCard.stability
        self.fsrsDifficulty = newCard.difficulty
        self.fsrsElapsedDays = newCard.elapsedDays
        self.fsrsScheduledDays = newCard.scheduledDays
        self.fsrsReps = newCard.reps
        self.fsrsLapses = newCard.lapses
        self.fsrsStatusRaw = 0  // .new
        self.fsrsLastReview = newCard.lastReview
    }

    /// Reconstruct a SwiftFSRS Card from stored fields
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

    /// Update stored fields from a SwiftFSRS Card after scheduling
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

    var accuracy: Double {
        totalAttempts > 0 ? Double(totalCorrect) / Double(totalAttempts) : 0
    }

    var isDue: Bool {
        fsrsDue <= Date()
    }

    var isNew: Bool {
        fsrsStatusRaw == 0
    }

    /// Convenience: the scheduled interval in days, used for mastery level thresholds
    var scheduledDays: Double {
        fsrsScheduledDays
    }
}
