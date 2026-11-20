import Foundation
import Testing
import SwiftData
@testable import JLPT_Grammar_Drill

/// Round-trips progress through `ProgressBackup` export → decode → restore
/// against in-memory stores.
@MainActor
struct ProgressBackupTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SRSRecord.self, StudyLog.self, AudioCard.self, AudioAttempt.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func roundTripRestoresAllModels() throws {
        // restore() writes this key; keep the host's value intact.
        let savedLastStudy = UserDefaults.standard.object(forKey: "lastStudyDate")
        defer { UserDefaults.standard.set(savedLastStudy, forKey: "lastStudyDate") }

        let source = try makeContext()
        let record = SRSRecord(grammarId: "n3_042")
        record.fsrsStability = 12.5
        record.fsrsStatusRaw = 2
        record.totalCorrect = 7
        record.totalAttempts = 9
        record.lastStudied = Date(timeIntervalSince1970: 1_790_000_000.25)
        source.insert(record)

        let log = StudyLog(dateKey: "2026-11-19", itemsStudied: 30, correctCount: 25)
        log.secondsStudied = 412
        source.insert(log)

        let card = AudioCard(exerciseId: "audio_n5_001")
        card.fsrsReps = 3
        card.introducedAt = Date(timeIntervalSince1970: 1_789_000_000)
        source.insert(card)

        let attempt = AudioAttempt(exerciseId: "audio_n5_001",
                                   rawTranscription: "こんにちは",
                                   normalizedTranscription: "こんにちは",
                                   bestMatchKanji: nil,
                                   matchScore: 0.92,
                                   thresholdUsed: 0.8,
                                   stripFinalCopulaUsed: false,
                                   passed: true,
                                   durationMs: 1500,
                                   fsrsGrade: 3)
        source.insert(attempt)
        try source.save()

        let data = try ProgressBackup.exportData(context: source)

        // Destination starts with stale data that must be replaced.
        let dest = try makeContext()
        dest.insert(SRSRecord(grammarId: "stale"))
        try dest.save()

        try ProgressBackup.restore(try ProgressBackup.decode(data), context: dest)

        let records = try dest.fetch(FetchDescriptor<SRSRecord>())
        #expect(records.count == 1)
        let r = try #require(records.first)
        #expect(r.grammarId == "n3_042")
        #expect(r.fsrsStability == 12.5)
        #expect(r.fsrsStatusRaw == 2)
        #expect(r.totalCorrect == 7)
        #expect(r.totalAttempts == 9)
        #expect(r.lastStudied == record.lastStudied)

        let logs = try dest.fetch(FetchDescriptor<StudyLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.secondsStudied == 412)

        let cards = try dest.fetch(FetchDescriptor<AudioCard>())
        #expect(cards.first?.fsrsReps == 3)
        #expect(cards.first?.introducedAt == card.introducedAt)

        let attempts = try dest.fetch(FetchDescriptor<AudioAttempt>())
        #expect(attempts.first?.id == attempt.id)
        #expect(attempts.first?.timestamp == attempt.timestamp)
        #expect(attempts.first?.fsrsGrade == 3)
    }

    @Test func undoLastImportRestoresPreviousProgress() throws {
        let savedLastStudy = UserDefaults.standard.object(forKey: "lastStudyDate")
        defer {
            UserDefaults.standard.set(savedLastStudy, forKey: "lastStudyDate")
            try? FileManager.default.removeItem(at: ProgressBackup.snapshotURL)
        }

        // Backup file contains one record.
        let source = try makeContext()
        source.insert(SRSRecord(grammarId: "from_backup"))
        try source.save()
        let backup = try ProgressBackup.decode(ProgressBackup.exportData(context: source))

        // Device currently has a different record.
        let device = try makeContext()
        let original = SRSRecord(grammarId: "original")
        original.totalCorrect = 5
        device.insert(original)
        try device.save()

        try ProgressBackup.importReplacingCurrent(backup, context: device)
        #expect(try device.fetch(FetchDescriptor<SRSRecord>()).map(\.grammarId) == ["from_backup"])
        #expect(ProgressBackup.snapshotDate() != nil)

        try ProgressBackup.undoLastImport(context: device)
        let restored = try device.fetch(FetchDescriptor<SRSRecord>())
        #expect(restored.map(\.grammarId) == ["original"])
        #expect(restored.first?.totalCorrect == 5)
        #expect(ProgressBackup.snapshotDate() == nil)
    }

    @Test func rejectsNewerFormatVersion() throws {
        let json = """
        {"formatVersion": 999, "exportedAt": 0, "srsRecords": [], "studyLogs": [],
         "audioCards": [], "audioAttempts": []}
        """
        #expect(throws: ProgressBackup.BackupError.self) {
            try ProgressBackup.decode(Data(json.utf8))
        }
    }
}
