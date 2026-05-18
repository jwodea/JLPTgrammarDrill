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
}
