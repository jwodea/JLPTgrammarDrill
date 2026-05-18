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

    /// Process a review and update the SRSRecord in place.
    static func processAnswer(record: SRSRecord, correct: Bool, reviewTime: Date = Date()) {
        let review = fsrsScheduler.schedule(
            card: record.fsrsCard,
            algorithm: FSRSAlgorithm.v5,
            reviewRating: rating(correct: correct),
            reviewTime: reviewTime
        )
        record.update(from: review.postReviewCard)
        record.totalAttempts += 1
        if correct { record.totalCorrect += 1 }
        record.lastStudied = reviewTime
    }
}
