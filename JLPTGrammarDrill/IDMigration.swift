import Foundation
import SwiftData

/// One-time migration of saved progress after the October 2026 corpus merge
/// (pattern-overlap audit). 205 pattern files were retired into surviving
/// files and exercises inside surviving files were renumbered, so saved
/// records keyed on the old IDs need re-keying.
///
/// Data comes from the bundled `id-migration-2026-10.json`. Its name has no
/// `nX_` prefix, so `GrammarLoader` ignores it.
///
/// - `patterns`: retired pattern id → surviving pattern id (`SRSRecord.grammarId`)
/// - `exercises`: pre-merge exercise id → post-merge exercise id, for every
///   exercise that survived (identity entries included)
/// - `touchedPatterns`: every pattern whose exercise IDs changed meaning. An
///   `AudioCard` in one of these patterns whose id is not in `exercises` points
///   at a dropped sentence and is deleted, because its id may now belong to a
///   different sentence.
/// - `resetExercises`: post-merge exercise ids whose sentence was rewritten
///   afterwards. Their audio progress belongs to the old sentence, so it is reset.
///
/// Runs once per install, guarded by a UserDefaults flag. If anything throws,
/// the flag stays unset and the migration is retried on next launch.
enum IDMigration {
    static let doneKey = "idMigration-2026-10-done"
    private static let resourceName = "id-migration-2026-10"

    // Internal (not private) so unit tests can drive the migration with a synthetic map.
    struct MapFile: Decodable {
        let patterns: [String: String]
        let exercises: [String: String]
        let touchedPatterns: [String]
        let resetExercises: [String]
    }

    @MainActor
    static func runIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode(MapFile.self, from: data) else {
            print("IDMigration: map not found or unreadable; skipping")
            return
        }
        let context = ModelContext(container)
        do {
            try migrateSRS(map: map, context: context)
            try migrateAudio(map: map, context: context)
            try context.save()
            defaults.set(true, forKey: doneKey)
        } catch {
            print("IDMigration failed, will retry next launch: \(error)")
            context.rollback()
        }
    }

    // MARK: - Grammar SRS (one record per pattern)

    static func migrateSRS(map: MapFile, context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<SRSRecord>())
        var byId: [String: SRSRecord] = [:]
        for r in records { byId[r.grammarId] = r }

        for r in records {
            guard let survivorId = map.patterns[r.grammarId] else { continue }
            if let existing = byId[survivorId], existing !== r {
                // Both the retired and the surviving pattern have progress:
                // keep the more advanced schedule and add up the attempt counts.
                let keepRetired = isMoreAdvanced(r.fsrsScheduledDays, r.fsrsReps,
                                                 than: existing.fsrsScheduledDays, existing.fsrsReps)
                if keepRetired {
                    existing.fsrsDue = r.fsrsDue
                    existing.fsrsStability = r.fsrsStability
                    existing.fsrsDifficulty = r.fsrsDifficulty
                    existing.fsrsElapsedDays = r.fsrsElapsedDays
                    existing.fsrsScheduledDays = r.fsrsScheduledDays
                    existing.fsrsReps = r.fsrsReps
                    existing.fsrsLapses = r.fsrsLapses
                    existing.fsrsStatusRaw = r.fsrsStatusRaw
                    existing.fsrsLastReview = r.fsrsLastReview
                }
                existing.totalCorrect += r.totalCorrect
                existing.totalAttempts += r.totalAttempts
                existing.lastStudied = latest(existing.lastStudied, r.lastStudied)
                byId[r.grammarId] = nil
                context.delete(r)
            } else {
                byId[r.grammarId] = nil
                r.grammarId = survivorId
                byId[survivorId] = r
            }
        }
    }

    // MARK: - Audio drill (one card per exercise) + attempt history

    static func migrateAudio(map: MapFile, context: ModelContext) throws {
        let touched = Set(map.touchedPatterns)
        let reset = Set(map.resetExercises)
        func patternId(of exerciseId: String) -> String {
            guard let i = exerciseId.lastIndex(of: "_") else { return exerciseId }
            return String(exerciseId[..<i])
        }
        func isTouched(_ exerciseId: String) -> Bool { touched.contains(patternId(of: exerciseId)) }

        // Cards. Re-key in two passes through temporary ids, because the old
        // and new id sets overlap and exerciseId is unique.
        let cards = try context.fetch(FetchDescriptor<AudioCard>())
        var pending: [(card: AudioCard, target: String)] = []
        for c in cards where isTouched(c.exerciseId) {
            if let target = map.exercises[c.exerciseId] {
                pending.append((c, target))
            } else {
                context.delete(c)          // sentence was dropped in the merge
            }
        }
        // Several old cards can map to one target only if a bug in the map
        // allowed it; keep the most advanced one.
        var winners: [String: AudioCard] = [:]
        for (c, target) in pending {
            if let w = winners[target] {
                if isMoreAdvanced(c.fsrsScheduledDays, c.fsrsReps, than: w.fsrsScheduledDays, w.fsrsReps) {
                    context.delete(w); winners[target] = c
                } else {
                    context.delete(c)
                }
            } else {
                winners[target] = c
            }
        }
        for (_, c) in winners { c.exerciseId = "__mig__" + c.exerciseId }
        try context.save()
        for (target, c) in winners {
            if reset.contains(target) {
                context.delete(c)          // sentence rewritten after the merge
            } else {
                c.exerciseId = target
            }
        }

        // Attempt history is not unique-keyed. Re-point rows whose sentence
        // survived unchanged. Rows for dropped or rewritten sentences are kept
        // but prefixed so they can't attach to a different sentence that now
        // has their old id.
        let attempts = try context.fetch(FetchDescriptor<AudioAttempt>())
        for a in attempts where isTouched(a.exerciseId) {
            if let target = map.exercises[a.exerciseId], !reset.contains(target) {
                a.exerciseId = target
            } else {
                a.exerciseId = "retired:" + a.exerciseId
            }
        }
    }

    // MARK: - Helpers

    private static func isMoreAdvanced(_ days: Double, _ reps: Int, than otherDays: Double, _ otherReps: Int) -> Bool {
        days != otherDays ? days > otherDays : reps > otherReps
    }

    private static func latest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (x?, y?): return max(x, y)
        default: return a ?? b
        }
    }
}
