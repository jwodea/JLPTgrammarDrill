import Testing
import SwiftData
@testable import BunpoTester

struct SRSEngineTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SRSRecord.self, configurations: config)
        return ModelContext(container)
    }

    private func makeRecord(
        context: ModelContext,
        grammarId: String = "test_001",
        difficulty: Double = 0.3,
        daysBetweenReviews: Double = 1.0,
        dateLastReviewed: Date = Date.now.addingTimeInterval(-86400) // 1 day ago by default
    ) -> SRSRecord {
        let record = SRSRecord(
            grammarId: grammarId,
            difficulty: difficulty,
            daysBetweenReviews: daysBetweenReviews,
            dateLastReviewed: dateLastReviewed
        )
        context.insert(record)
        return record
    }

    @Test func correctAnswerIncreasesInterval() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        let oldInterval = record.daysBetweenReviews
        SRSEngine.processAnswer(record: record, correct: true)
        #expect(record.daysBetweenReviews > oldInterval)
    }

    @Test func incorrectAnswerDecreasesInterval() throws {
        let context = try makeContext()
        let record = makeRecord(context: context, daysBetweenReviews: 10.0,
            dateLastReviewed: Date.now.addingTimeInterval(-10 * 86400))
        SRSEngine.processAnswer(record: record, correct: false)
        #expect(record.daysBetweenReviews < 10.0)
    }

    @Test func incorrectAnswerIncreasesDifficulty() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        let oldDifficulty = record.difficulty
        SRSEngine.processAnswer(record: record, correct: false)
        #expect(record.difficulty > oldDifficulty)
    }

    @Test func correctAnswerDecreasesDifficulty() throws {
        let context = try makeContext()
        let record = makeRecord(context: context, difficulty: 0.5)
        let oldDifficulty = record.difficulty
        SRSEngine.processAnswer(record: record, correct: true)
        #expect(record.difficulty < oldDifficulty)
    }

    @Test func difficultyClampedToZeroOne() throws {
        let context = try makeContext()

        // Very easy item answered correctly — difficulty should not go below 0
        let easyRecord = makeRecord(context: context, grammarId: "easy", difficulty: 0.01)
        SRSEngine.processAnswer(record: easyRecord, correct: true)
        #expect(easyRecord.difficulty >= 0.0)

        // Very hard item answered incorrectly — difficulty should not exceed 1
        let hardRecord = makeRecord(context: context, grammarId: "hard", difficulty: 0.99)
        SRSEngine.processAnswer(record: hardRecord, correct: false)
        #expect(hardRecord.difficulty <= 1.0)
    }

    @Test func earlyReviewGivesLessCredit() throws {
        let context = try makeContext()

        // Reviewed at 50% of interval (early)
        let earlyRecord = makeRecord(context: context, grammarId: "early",
            daysBetweenReviews: 10.0,
            dateLastReviewed: Date.now.addingTimeInterval(-5 * 86400))
        let earlyOldInterval = earlyRecord.daysBetweenReviews
        SRSEngine.processAnswer(record: earlyRecord, correct: true)
        let earlyGrowth = earlyRecord.daysBetweenReviews / earlyOldInterval

        // Reviewed at 100% of interval (on time)
        let onTimeRecord = makeRecord(context: context, grammarId: "ontime",
            daysBetweenReviews: 10.0,
            dateLastReviewed: Date.now.addingTimeInterval(-10 * 86400))
        let onTimeOldInterval = onTimeRecord.daysBetweenReviews
        SRSEngine.processAnswer(record: onTimeRecord, correct: true)
        let onTimeGrowth = onTimeRecord.daysBetweenReviews / onTimeOldInterval

        // On-time review should grow more than early review
        #expect(onTimeGrowth > earlyGrowth)
    }

    @Test func dateLastReviewedUpdatedToNow() throws {
        let context = try makeContext()
        let record = makeRecord(context: context)
        SRSEngine.processAnswer(record: record, correct: true)
        let secondsSinceReview = Date.now.timeIntervalSince(record.dateLastReviewed)
        #expect(secondsSinceReview < 1.0)
    }

    @Test func minimumIntervalFloor() throws {
        let context = try makeContext()
        // Very hard item reviewed incorrectly — interval should not go below 0.5
        let record = makeRecord(context: context, difficulty: 0.9, daysBetweenReviews: 1.0)
        SRSEngine.processAnswer(record: record, correct: false)
        #expect(record.daysBetweenReviews >= 0.5)
    }

    @Test func overdueCorrectAnswerGrowsMoreThanOnTime() throws {
        let context = try makeContext()

        // 2x overdue (the cap)
        let overdueRecord = makeRecord(context: context, grammarId: "overdue",
            daysBetweenReviews: 5.0,
            dateLastReviewed: Date.now.addingTimeInterval(-10 * 86400))
        let overdueOld = overdueRecord.daysBetweenReviews
        SRSEngine.processAnswer(record: overdueRecord, correct: true)
        let overdueGrowth = overdueRecord.daysBetweenReviews / overdueOld

        // Exactly on time
        let onTimeRecord = makeRecord(context: context, grammarId: "ontime",
            daysBetweenReviews: 5.0,
            dateLastReviewed: Date.now.addingTimeInterval(-5 * 86400))
        let onTimeOld = onTimeRecord.daysBetweenReviews
        SRSEngine.processAnswer(record: onTimeRecord, correct: true)
        let onTimeGrowth = onTimeRecord.daysBetweenReviews / onTimeOld

        #expect(overdueGrowth > onTimeGrowth)
    }
}
