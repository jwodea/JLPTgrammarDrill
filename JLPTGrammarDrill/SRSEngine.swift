import Foundation
import SwiftData
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

    /// Fast-forward a pattern to a long interval, as if it had been answered
    /// correctly ten times over the past month. Used by "Mark as Known" in the
    /// browser and during a drill session.
    static func markKnown(grammarId: String, context: ModelContext) {
        let descriptor = FetchDescriptor<SRSRecord>(
            predicate: #Predicate { $0.grammarId == grammarId }
        )
        let record = (try? context.fetch(descriptor).first) ?? {
            let r = SRSRecord(grammarId: grammarId)
            context.insert(r)
            return r
        }()
        var card = Card()
        let now = Date()
        for i in 0..<10 {
            let reviewDate = now.addingTimeInterval(-Double(10 - i) * 86400 * 3)
            let review = fsrsScheduler.schedule(
                card: card,
                algorithm: FSRSAlgorithm.v5,
                reviewRating: .good,
                reviewTime: reviewDate
            )
            card = review.postReviewCard
        }
        record.update(from: card)
        record.totalAttempts = max(record.totalAttempts, 10)
        record.totalCorrect = max(record.totalCorrect, 10)
        record.lastStudied = now
        try? context.save()
    }
}
