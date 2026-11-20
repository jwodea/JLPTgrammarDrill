import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Serializes every progress-bearing SwiftData model (plus the last-study-date
/// default) to a single JSON file the user can save outside the app sandbox,
/// so progress survives deleting and reinstalling the app.
enum ProgressBackup {
    /// Bump when the payload shape changes incompatibly.
    static let formatVersion = 1

    enum BackupError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "This backup was made by a newer version of the app (format \(v)). Update the app and try again."
            }
        }
    }

    struct Payload: Codable {
        var formatVersion: Int
        var exportedAt: Date
        var lastStudyDate: Double?
        var srsRecords: [SRSRecordDTO]
        var studyLogs: [StudyLogDTO]
        var audioCards: [AudioCardDTO]
        var audioAttempts: [AudioAttemptDTO]
    }

    struct SRSRecordDTO: Codable {
        var grammarId: String
        var fsrsDue: Date
        var fsrsStability: Double
        var fsrsDifficulty: Double
        var fsrsElapsedDays: Double
        var fsrsScheduledDays: Double
        var fsrsReps: Int
        var fsrsLapses: Int
        var fsrsStatusRaw: Int
        var fsrsLastReview: Date?
        var totalCorrect: Int
        var totalAttempts: Int
        var lastStudied: Date?
    }

    struct StudyLogDTO: Codable {
        var dateKey: String
        var itemsStudied: Int
        var correctCount: Int
        var secondsStudied: Double
    }

    struct AudioCardDTO: Codable {
        var exerciseId: String
        var fsrsDue: Date
        var fsrsStability: Double
        var fsrsDifficulty: Double
        var fsrsElapsedDays: Double
        var fsrsScheduledDays: Double
        var fsrsReps: Int
        var fsrsLapses: Int
        var fsrsStatusRaw: Int
        var fsrsLastReview: Date?
        var introducedAt: Date?
    }

    struct AudioAttemptDTO: Codable {
        var id: UUID
        var exerciseId: String
        var timestamp: Date
        var rawTranscription: String
        var normalizedTranscription: String
        var bestMatchKanji: String?
        var matchScore: Double
        var thresholdUsed: Double
        var stripFinalCopulaUsed: Bool
        var passed: Bool
        var fsrsGrade: Int?
        var durationMs: Int
        var synthetic: Bool
    }

    // MARK: - Export

    static func exportData(context: ModelContext) throws -> Data {
        let records = try context.fetch(FetchDescriptor<SRSRecord>())
        let logs = try context.fetch(FetchDescriptor<StudyLog>())
        let cards = try context.fetch(FetchDescriptor<AudioCard>())
        let attempts = try context.fetch(FetchDescriptor<AudioAttempt>())

        let lastStudy = UserDefaults.standard.object(forKey: "lastStudyDate") as? Double

        let payload = Payload(
            formatVersion: formatVersion,
            exportedAt: .now,
            lastStudyDate: lastStudy,
            srsRecords: records.map {
                SRSRecordDTO(grammarId: $0.grammarId,
                             fsrsDue: $0.fsrsDue,
                             fsrsStability: $0.fsrsStability,
                             fsrsDifficulty: $0.fsrsDifficulty,
                             fsrsElapsedDays: $0.fsrsElapsedDays,
                             fsrsScheduledDays: $0.fsrsScheduledDays,
                             fsrsReps: $0.fsrsReps,
                             fsrsLapses: $0.fsrsLapses,
                             fsrsStatusRaw: $0.fsrsStatusRaw,
                             fsrsLastReview: $0.fsrsLastReview,
                             totalCorrect: $0.totalCorrect,
                             totalAttempts: $0.totalAttempts,
                             lastStudied: $0.lastStudied)
            },
            studyLogs: logs.map {
                StudyLogDTO(dateKey: $0.dateKey,
                            itemsStudied: $0.itemsStudied,
                            correctCount: $0.correctCount,
                            secondsStudied: $0.secondsStudied)
            },
            audioCards: cards.map {
                AudioCardDTO(exerciseId: $0.exerciseId,
                             fsrsDue: $0.fsrsDue,
                             fsrsStability: $0.fsrsStability,
                             fsrsDifficulty: $0.fsrsDifficulty,
                             fsrsElapsedDays: $0.fsrsElapsedDays,
                             fsrsScheduledDays: $0.fsrsScheduledDays,
                             fsrsReps: $0.fsrsReps,
                             fsrsLapses: $0.fsrsLapses,
                             fsrsStatusRaw: $0.fsrsStatusRaw,
                             fsrsLastReview: $0.fsrsLastReview,
                             introducedAt: $0.introducedAt)
            },
            audioAttempts: attempts.map {
                AudioAttemptDTO(id: $0.id,
                                exerciseId: $0.exerciseId,
                                timestamp: $0.timestamp,
                                rawTranscription: $0.rawTranscription,
                                normalizedTranscription: $0.normalizedTranscription,
                                bestMatchKanji: $0.bestMatchKanji,
                                matchScore: $0.matchScore,
                                thresholdUsed: $0.thresholdUsed,
                                stripFinalCopulaUsed: $0.stripFinalCopulaUsed,
                                passed: $0.passed,
                                fsrsGrade: $0.fsrsGrade,
                                durationMs: $0.durationMs,
                                synthetic: $0.synthetic)
            }
        )

        let encoder = JSONEncoder()
        // Date's native reference-date encoding round-trips exactly; ISO 8601
        // drops sub-seconds and seconds-since-1970 picks up rounding error.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    // MARK: - Import

    /// Decodes and validates the file without touching the store.
    static func decode(_ data: Data) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let payload = try decoder.decode(Payload.self, from: data)
        guard payload.formatVersion <= formatVersion else {
            throw BackupError.unsupportedVersion(payload.formatVersion)
        }
        return payload
    }

    // MARK: - Pre-import snapshot

    /// How long the automatic pre-import snapshot is kept for "Undo Last Import".
    static let snapshotLifetime: TimeInterval = 24 * 60 * 60

    /// Single snapshot file, overwritten by each import. Lives in Application
    /// Support so it's private to the app but not purged like Caches.
    static var snapshotURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("ProgressBackups", isDirectory: true)
            .appendingPathComponent("pre-import.json")
    }

    /// When the current snapshot was taken, or nil if there is none. Deletes
    /// the snapshot as a side effect once it's older than `snapshotLifetime`.
    static func snapshotDate() -> Date? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: snapshotURL.path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        guard Date().timeIntervalSince(date) < snapshotLifetime else {
            try? fm.removeItem(at: snapshotURL)
            return nil
        }
        return date
    }

    /// Snapshots current progress, then replaces it with `payload`. If the
    /// restore fails partway, the snapshot is put back so the user is never
    /// left with an empty store.
    static func importReplacingCurrent(_ payload: Payload, context: ModelContext) throws {
        let snapshot = try exportData(context: context)
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try snapshot.write(to: snapshotURL, options: .atomic)

        do {
            try restore(payload, context: context)
        } catch {
            context.rollback()
            try? restore(decode(snapshot), context: context)
            throw error
        }
    }

    /// Restores the pre-import snapshot and discards it.
    static func undoLastImport(context: ModelContext) throws {
        let data = try Data(contentsOf: snapshotURL)
        try restore(decode(data), context: context)
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    /// Replaces all current progress with the payload's contents.
    static func restore(_ payload: Payload, context: ModelContext) throws {
        // Clear first and save, so inserts don't collide with existing
        // @Attribute(.unique) keys in the same transaction.
        try context.delete(model: SRSRecord.self)
        try context.delete(model: StudyLog.self)
        try context.delete(model: AudioCard.self)
        try context.delete(model: AudioAttempt.self)
        try context.save()

        for dto in payload.srsRecords {
            let r = SRSRecord(grammarId: dto.grammarId)
            r.fsrsDue = dto.fsrsDue
            r.fsrsStability = dto.fsrsStability
            r.fsrsDifficulty = dto.fsrsDifficulty
            r.fsrsElapsedDays = dto.fsrsElapsedDays
            r.fsrsScheduledDays = dto.fsrsScheduledDays
            r.fsrsReps = dto.fsrsReps
            r.fsrsLapses = dto.fsrsLapses
            r.fsrsStatusRaw = dto.fsrsStatusRaw
            r.fsrsLastReview = dto.fsrsLastReview
            r.totalCorrect = dto.totalCorrect
            r.totalAttempts = dto.totalAttempts
            r.lastStudied = dto.lastStudied
            context.insert(r)
        }

        for dto in payload.studyLogs {
            let log = StudyLog(dateKey: dto.dateKey,
                               itemsStudied: dto.itemsStudied,
                               correctCount: dto.correctCount)
            log.secondsStudied = dto.secondsStudied
            context.insert(log)
        }

        for dto in payload.audioCards {
            let c = AudioCard(exerciseId: dto.exerciseId)
            c.fsrsDue = dto.fsrsDue
            c.fsrsStability = dto.fsrsStability
            c.fsrsDifficulty = dto.fsrsDifficulty
            c.fsrsElapsedDays = dto.fsrsElapsedDays
            c.fsrsScheduledDays = dto.fsrsScheduledDays
            c.fsrsReps = dto.fsrsReps
            c.fsrsLapses = dto.fsrsLapses
            c.fsrsStatusRaw = dto.fsrsStatusRaw
            c.fsrsLastReview = dto.fsrsLastReview
            c.introducedAt = dto.introducedAt
            context.insert(c)
        }

        for dto in payload.audioAttempts {
            let a = AudioAttempt(exerciseId: dto.exerciseId,
                                 rawTranscription: dto.rawTranscription,
                                 normalizedTranscription: dto.normalizedTranscription,
                                 bestMatchKanji: dto.bestMatchKanji,
                                 matchScore: dto.matchScore,
                                 thresholdUsed: dto.thresholdUsed,
                                 stripFinalCopulaUsed: dto.stripFinalCopulaUsed,
                                 passed: dto.passed,
                                 durationMs: dto.durationMs,
                                 synthetic: dto.synthetic,
                                 fsrsGrade: dto.fsrsGrade)
            a.id = dto.id
            a.timestamp = dto.timestamp
            context.insert(a)
        }

        try context.save()

        if let lastStudy = payload.lastStudyDate {
            UserDefaults.standard.set(lastStudy, forKey: "lastStudyDate")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastStudyDate")
        }
    }

    static func defaultFilename() -> String {
        "JLPT-Grammar-Progress-\(StudyLog.todayKey())"
    }
}

/// Wraps pre-encoded backup JSON for `.fileExporter`.
struct ProgressBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
