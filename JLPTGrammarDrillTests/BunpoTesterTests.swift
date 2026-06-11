import Foundation
import Testing
import SwiftData
import SwiftFSRS
@testable import JLPT_Grammar_Drill

@MainActor
struct SRSEngineTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SRSRecord.self, configurations: config)
        return ModelContext(container)
    }

    private func makeRecord(context: ModelContext, grammarId: String = "test_001") -> SRSRecord {
        let record = SRSRecord(grammarId: grammarId)
        context.insert(record)
        return record
    }

    /// Walk a freshly-created card into FSRS `.review` status with successful answers.
    /// New → learning (after first good) → review (after second good).
    private func driveIntoReview(record: SRSRecord, startingAt: Date) -> Date {
        var t = startingAt
        SRSEngine.processAnswer(record: record, correct: true, reviewTime: t)
        t = t.addingTimeInterval(max(record.fsrsScheduledDays, 1) * 86_400 + 1)
        SRSEngine.processAnswer(record: record, correct: true, reviewTime: t)
        return t
    }

    @Test func correctAnswerIncrementsCounters() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        let now = Date()
        SRSEngine.processAnswer(record: record, correct: true, reviewTime: now)
        #expect(record.totalAttempts == 1)
        #expect(record.totalCorrect == 1)
        #expect(record.lastStudied == now)
    }

    @Test func incorrectAnswerDoesNotIncrementCorrect() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        SRSEngine.processAnswer(record: record, correct: false)
        #expect(record.totalAttempts == 1)
        #expect(record.totalCorrect == 0)
    }

    @Test func newCardLeavesNewStatusAfterFirstAnswer() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        #expect(record.isNew)
        SRSEngine.processAnswer(record: record, correct: true)
        #expect(!record.isNew)
    }

    @Test func correctAnswerSchedulesFutureDueDate() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        let now = Date()
        SRSEngine.processAnswer(record: record, correct: true, reviewTime: now)
        #expect(record.fsrsDue > now)
    }

    @Test func twoSuccessfulAnswersReachReviewStatus() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        _ = driveIntoReview(record: record, startingAt: Date.now.addingTimeInterval(-30 * 86_400))
        // fsrsStatusRaw == 2 corresponds to .review (see SRSRecord.update).
        #expect(record.fsrsStatusRaw == 2)
        #expect(record.fsrsScheduledDays > 0)
    }

    @Test func failedReviewIncrementsLapses() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        let t = driveIntoReview(record: record, startingAt: Date.now.addingTimeInterval(-30 * 86_400))
        let lapsesBefore = record.fsrsLapses
        SRSEngine.processAnswer(record: record, correct: false, reviewTime: t.addingTimeInterval(86_400))
        #expect(record.fsrsLapses == lapsesBefore + 1)
    }

    @Test func srsRecordRoundTripsThroughFsrsCard() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        SRSEngine.processAnswer(record: record, correct: true)
        let card = record.fsrsCard
        #expect(card.due == record.fsrsDue)
        #expect(card.stability == record.fsrsStability)
        #expect(card.difficulty == record.fsrsDifficulty)
        #expect(card.reps == record.fsrsReps)
    }

    @Test func accuracyTracksCorrectOverAttempts() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        SRSEngine.processAnswer(record: record, correct: true)
        SRSEngine.processAnswer(record: record, correct: false)
        SRSEngine.processAnswer(record: record, correct: true)
        #expect(record.totalAttempts == 3)
        #expect(record.totalCorrect == 2)
        #expect(abs(record.accuracy - 2.0 / 3.0) < 1e-9)
    }

    // MARK: - Aggregate rating (per-pattern session cadence)

    @Test func aggregateRatingAllCorrectIsGood() {
        #expect(SRSEngine.aggregateRating(correct: 3, total: 3) == .good)
        #expect(SRSEngine.aggregateRating(correct: 1, total: 1) == .good)
    }

    @Test func aggregateRatingMajorityIsHard() {
        #expect(SRSEngine.aggregateRating(correct: 2, total: 3) == .hard)
        #expect(SRSEngine.aggregateRating(correct: 1, total: 2) == .hard)
        #expect(SRSEngine.aggregateRating(correct: 3, total: 5) == .hard)
    }

    @Test func aggregateRatingMinorityIsAgain() {
        #expect(SRSEngine.aggregateRating(correct: 1, total: 3) == .again)
        #expect(SRSEngine.aggregateRating(correct: 0, total: 3) == .again)
        #expect(SRSEngine.aggregateRating(correct: 0, total: 1) == .again)
    }

    @Test func aggregateRatingZeroAttemptsReturnsNil() {
        #expect(SRSEngine.aggregateRating(correct: 0, total: 0) == nil)
    }

    /// Three intro sentences answered correctly should advance a new card exactly
    /// like ONE `.good` review — not blow past `.learning` straight into `.review`
    /// the way three rapid-fire `processAnswer` calls used to.
    @Test func aggregatePathOnNewCardLandsInLearning() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        SRSEngine.applyRating(record: record, rating: .good, attemptsDelta: 3, correctDelta: 3)
        // fsrsStatusRaw == 1 corresponds to .learning (see SRSRecord.update).
        #expect(record.fsrsStatusRaw == 1)
        #expect(record.totalAttempts == 3)
        #expect(record.totalCorrect == 3)
    }

    /// A `.hard` aggregate (e.g. 2/3 first-try correct) should still leave the card
    /// in `.learning` after one session — bumping it to `.review` requires another
    /// successful session, matching the FSRS short-term step convention.
    @Test func aggregatePathHardKeepsCardInLearning() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        SRSEngine.applyRating(record: record, rating: .hard, attemptsDelta: 3, correctDelta: 2)
        #expect(record.fsrsStatusRaw == 1)
        #expect(record.totalAttempts == 3)
        #expect(record.totalCorrect == 2)
    }

    /// `.again` on a new card stays in `.learning` with a near-immediate due date —
    /// no lapse counted because the card was never in `.review` to begin with.
    @Test func aggregatePathAgainOnNewCardDoesNotLapse() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        let lapsesBefore = record.fsrsLapses
        SRSEngine.applyRating(record: record, rating: .again, attemptsDelta: 3, correctDelta: 0)
        #expect(record.fsrsLapses == lapsesBefore)
        #expect(record.fsrsStatusRaw == 1)
    }

    /// Compared to the old behavior (three back-to-back `.good` calls), the aggregate
    /// path should leave the card with a meaningfully shorter due date — one short-term
    /// step away, not days into the future.
    @Test func aggregatePathSchedulesShorterThanThreeRapidGoods() throws {
        let context = try makeContext()
        let now = Date()

        let aggregateRecord = makeRecord(context: context, grammarId: "agg")
        SRSEngine.applyRating(record: aggregateRecord, rating: .good,
                              attemptsDelta: 3, correctDelta: 3, reviewTime: now)

        let rapidRecord = makeRecord(context: context, grammarId: "rapid")
        SRSEngine.processAnswer(record: rapidRecord, correct: true, reviewTime: now)
        SRSEngine.processAnswer(record: rapidRecord, correct: true, reviewTime: now)
        SRSEngine.processAnswer(record: rapidRecord, correct: true, reviewTime: now)

        #expect(aggregateRecord.fsrsDue < rapidRecord.fsrsDue)
        #expect(aggregateRecord.fsrsStatusRaw == 1) // .learning
        #expect(rapidRecord.fsrsStatusRaw == 2)     // .review — overshot
    }
}
