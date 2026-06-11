import Foundation
import SwiftFSRS

/// Shared FSRS scheduler. SwiftFSRS' `ShortTermScheduler()` initializer is
/// internal to the module, but `SchedulerType.shortTerm.implementation` is
/// the library's public entry point and returns the same value.
nonisolated let fsrsScheduler: any Scheduler = SchedulerType.shortTerm.implementation

struct SRSEngine {
    /// Map a binary correct/wrong result to an FSRS Rating.
    ///
    /// FSRS uses four grades: .again, .hard, .good, .easy
    /// For a grammar cloze exercise with no self-report nuance:
    /// - Wrong answer → .again  (forgot — reset to short interval)
    /// - Correct answer → .good (default successful recall)
    private static func rating(correct: Bool) -> Rating {
        correct ? Rating.good : Rating.again
    }

    /// Roll up first-attempt outcomes across all variations of one pattern shown
    /// in a single session into one FSRS rating. Grammar patterns are spread across
    /// many sentences but represent a single SRS "card", so FSRS expects exactly one
    /// review event per session — not one per sentence.
    /// - 100% first-try correct → `.good`
    /// - ≥ 50% first-try correct → `.hard`
    /// - < 50% first-try correct → `.again`
    /// Returns `nil` when no attempts were recorded (caller should skip the update).
    static func aggregateRating(correct: Int, total: Int) -> Rating? {
        guard total > 0 else { return nil }
        if correct == total { return .good }
        if correct * 2 >= total { return .hard }
        return .again
    }

    /// Apply an explicit FSRS rating to a record. Used by the per-pattern aggregate path
    /// in `ExerciseView`, which defers FSRS until the end of the session and emits one
    /// rating per pattern. `attemptsDelta` / `correctDelta` let callers reflect every
    /// on-screen answer (including retries) in the local accuracy counters, even though
    /// only one FSRS event is recorded.
    static func applyRating(
        record: SRSRecord,
        rating: Rating,
        attemptsDelta: Int = 0,
        correctDelta: Int = 0,
        reviewTime: Date = Date()
    ) {
        let review = fsrsScheduler.schedule(
            card: record.fsrsCard,
            algorithm: FSRSAlgorithm.v5,
            reviewRating: rating,
            reviewTime: reviewTime
        )
        record.update(from: review.postReviewCard)
        record.totalAttempts += attemptsDelta
        record.totalCorrect += correctDelta
        record.lastStudied = reviewTime
    }

    /// Process a single review and update the SRSRecord in place.
    /// Used by callers that genuinely rate one answer at a time (particle practice,
    /// older tests). The grammar drill aggregates via `applyRating` instead.
    static func processAnswer(record: SRSRecord, correct: Bool, reviewTime: Date = Date()) {
        applyRating(
            record: record,
            rating: rating(correct: correct),
            attemptsDelta: 1,
            correctDelta: correct ? 1 : 0,
            reviewTime: reviewTime
        )
    }
}
