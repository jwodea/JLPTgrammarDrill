import Foundation
import Testing
import SwiftData
@testable import JLPT_Grammar_Drill

/// Drives `IDMigration.migrateSRS` / `migrateAudio` against an in-memory store
/// with synthetic maps, covering re-keying, merging, dropping, and resets.
@MainActor
struct IDMigrationTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SRSRecord.self, AudioCard.self, AudioAttempt.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeMap(
        patterns: [String: String] = [:],
        exercises: [String: String] = [:],
        touchedPatterns: [String] = [],
        resetExercises: [String] = []
    ) -> IDMigration.MapFile {
        IDMigration.MapFile(
            patterns: patterns,
            exercises: exercises,
            touchedPatterns: touchedPatterns,
            resetExercises: resetExercises
        )
    }

    private func makeAttempt(context: ModelContext, exerciseId: String) -> AudioAttempt {
        let attempt = AudioAttempt(
            exerciseId: exerciseId,
            rawTranscription: "raw",
            normalizedTranscription: "norm",
            bestMatchKanji: nil,
            matchScore: 1.0,
            thresholdUsed: 0.8,
            stripFinalCopulaUsed: false,
            passed: true,
            durationMs: 100
        )
        context.insert(attempt)
        return attempt
    }

    // MARK: - Grammar SRS

    @Test func retiredPatternIsRekeyedToSurvivor() throws {
        let context = try makeContext()
        let record = SRSRecord(grammarId: "n4_900")
        context.insert(record)

        try IDMigration.migrateSRS(map: makeMap(patterns: ["n4_900": "n4_001"]), context: context)
        try context.save()

        #expect(record.grammarId == "n4_001")
    }

    @Test func unmappedPatternIsUntouched() throws {
        let context = try makeContext()
        let record = SRSRecord(grammarId: "n4_002")
        context.insert(record)

        try IDMigration.migrateSRS(map: makeMap(patterns: ["n4_900": "n4_001"]), context: context)
        try context.save()

        #expect(record.grammarId == "n4_002")
    }

    @Test func mergeKeepsMoreAdvancedRetiredScheduleAndSumsCounts() throws {
        let context = try makeContext()
        let retired = SRSRecord(grammarId: "n4_900")
        retired.fsrsScheduledDays = 30
        retired.fsrsReps = 10
        retired.totalCorrect = 8
        retired.totalAttempts = 10
        let survivor = SRSRecord(grammarId: "n4_001")
        survivor.fsrsScheduledDays = 5
        survivor.fsrsReps = 3
        survivor.totalCorrect = 2
        survivor.totalAttempts = 4
        context.insert(retired)
        context.insert(survivor)

        try IDMigration.migrateSRS(map: makeMap(patterns: ["n4_900": "n4_001"]), context: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<SRSRecord>())
        #expect(remaining.count == 1)
        let merged = try #require(remaining.first)
        #expect(merged.grammarId == "n4_001")
        #expect(merged.fsrsScheduledDays == 30)   // retired schedule was more advanced
        #expect(merged.fsrsReps == 10)
        #expect(merged.totalCorrect == 10)        // 8 + 2
        #expect(merged.totalAttempts == 14)       // 10 + 4
    }

    @Test func mergeKeepsMoreAdvancedSurvivorSchedule() throws {
        let context = try makeContext()
        let retired = SRSRecord(grammarId: "n4_900")
        retired.fsrsScheduledDays = 2
        retired.totalAttempts = 3
        let survivor = SRSRecord(grammarId: "n4_001")
        survivor.fsrsScheduledDays = 60
        survivor.totalAttempts = 7
        context.insert(retired)
        context.insert(survivor)

        try IDMigration.migrateSRS(map: makeMap(patterns: ["n4_900": "n4_001"]), context: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<SRSRecord>())
        #expect(remaining.count == 1)
        let merged = try #require(remaining.first)
        #expect(merged.fsrsScheduledDays == 60)   // survivor schedule kept
        #expect(merged.totalAttempts == 10)       // counts still summed
    }

    // MARK: - Audio cards

    @Test func touchedCardIsRekeyed() throws {
        let context = try makeContext()
        let card = AudioCard(exerciseId: "n4_008_1")
        context.insert(card)

        let map = makeMap(exercises: ["n4_008_1": "n4_008_3"], touchedPatterns: ["n4_008"])
        try IDMigration.migrateAudio(map: map, context: context)
        try context.save()

        #expect(card.exerciseId == "n4_008_3")
    }

    @Test func swappedIdsSurviveUniqueConstraint() throws {
        // Two cards exchange ids — the two-pass temp-id approach must avoid
        // tripping the unique constraint on exerciseId.
        let context = try makeContext()
        let a = AudioCard(exerciseId: "n4_008_1")
        a.fsrsReps = 1
        let b = AudioCard(exerciseId: "n4_008_2")
        b.fsrsReps = 2
        context.insert(a)
        context.insert(b)

        let map = makeMap(
            exercises: ["n4_008_1": "n4_008_2", "n4_008_2": "n4_008_1"],
            touchedPatterns: ["n4_008"]
        )
        try IDMigration.migrateAudio(map: map, context: context)
        try context.save()

        let cards = try context.fetch(FetchDescriptor<AudioCard>())
        #expect(cards.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: cards.map { ($0.exerciseId, $0) })
        #expect(byId["n4_008_2"]?.fsrsReps == 1)  // was n4_008_1
        #expect(byId["n4_008_1"]?.fsrsReps == 2)  // was n4_008_2
    }

    @Test func droppedSentenceCardIsDeleted() throws {
        let context = try makeContext()
        let card = AudioCard(exerciseId: "n4_008_9")
        context.insert(card)

        // Pattern is touched but the exercise id has no mapping → sentence dropped.
        let map = makeMap(exercises: ["n4_008_1": "n4_008_1"], touchedPatterns: ["n4_008"])
        try IDMigration.migrateAudio(map: map, context: context)
        try context.save()

        let cards = try context.fetch(FetchDescriptor<AudioCard>())
        #expect(cards.isEmpty)
    }

    @Test func rewrittenSentenceCardIsDeleted() throws {
        let context = try makeContext()
        let card = AudioCard(exerciseId: "n4_008_1")
        context.insert(card)

        let map = makeMap(
            exercises: ["n4_008_1": "n4_008_2"],
            touchedPatterns: ["n4_008"],
            resetExercises: ["n4_008_2"]
        )
        try IDMigration.migrateAudio(map: map, context: context)
        try context.save()

        let cards = try context.fetch(FetchDescriptor<AudioCard>())
        #expect(cards.isEmpty)
    }

    @Test func untouchedPatternCardIsLeftAlone() throws {
        let context = try makeContext()
        let card = AudioCard(exerciseId: "n5_001_1")
        context.insert(card)

        let map = makeMap(exercises: ["n4_008_1": "n4_008_2"], touchedPatterns: ["n4_008"])
        try IDMigration.migrateAudio(map: map, context: context)
        try context.save()

        #expect(card.exerciseId == "n5_001_1")
    }

    // MARK: - Audio attempt history

    @Test func survivingAttemptIsRepointed() throws {
        let context = try makeContext()
        let attempt = makeAttempt(context: context, exerciseId: "n4_008_1")

        let map = makeMap(exercises: ["n4_008_1": "n4_008_3"], touchedPatterns: ["n4_008"])
        try IDMigration.migrateAudio(map: map, context: context)
        try context.save()

        #expect(attempt.exerciseId == "n4_008_3")
    }

    @Test func droppedAttemptIsRetiredNotDeleted() throws {
        let context = try makeContext()
        let attempt = makeAttempt(context: context, exerciseId: "n4_008_9")

        let map = makeMap(exercises: [:], touchedPatterns: ["n4_008"])
        try IDMigration.migrateAudio(map: map, context: context)
        try context.save()

        #expect(attempt.exerciseId == "retired:n4_008_9")
        #expect(try context.fetch(FetchDescriptor<AudioAttempt>()).count == 1)
    }

    @Test func rewrittenSentenceAttemptIsRetired() throws {
        let context = try makeContext()
        let attempt = makeAttempt(context: context, exerciseId: "n4_008_1")

        let map = makeMap(
            exercises: ["n4_008_1": "n4_008_2"],
            touchedPatterns: ["n4_008"],
            resetExercises: ["n4_008_2"]
        )
        try IDMigration.migrateAudio(map: map, context: context)
        try context.save()

        #expect(attempt.exerciseId == "retired:n4_008_1")
    }
}
