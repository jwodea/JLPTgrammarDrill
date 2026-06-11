import Foundation

/// Free-tier gating rules.
///
/// The first 20 grammar patterns per JLPT level are free. All particles are
/// free. The first 20 audio-eligible sentences per JLPT level are free.
/// Everything else requires the unlock IAP.
enum Entitlement {
    /// Number of free items per level for both grammar and audio.
    static let freeItemsPerLevel = 20

    /// Synchronous read of the IAP unlock state. Mirrors `StoreManager.isUnlocked`
    /// via UserDefaults so that loaders / static helpers can gate content without
    /// touching the `@Observable` store.
    static var isFullUnlocked: Bool {
        UserDefaults.standard.bool(forKey: StoreManager.unlockedDefaultsKey)
    }

    /// Returns the set of free grammar pattern IDs: the first 20 patterns per level
    /// when sorted by ID. Returns `nil` (meaning "all unlocked") if the user owns
    /// the full version.
    static func freeGrammarIds(from patternFiles: [PatternFile]) -> Set<String>? {
        guard !isFullUnlocked else { return nil }
        var byLevel: [String: [PatternFile]] = [:]
        for pf in patternFiles {
            byLevel[pf.level, default: []].append(pf)
        }
        var free: Set<String> = []
        for (_, files) in byLevel {
            let firstN = files.sorted { $0.id < $1.id }.prefix(freeItemsPerLevel)
            free.formUnion(firstN.map(\.id))
        }
        return free
    }

    /// Returns the set of free audio exercise IDs: the first 20 audio-eligible
    /// exercises per level when sorted by canonical loader order (pattern id, then
    /// exercise sequence). Returns `nil` if the user owns the full version.
    static func freeAudioIds(from exercises: [AudioExercise]) -> Set<String>? {
        guard !isFullUnlocked else { return nil }
        var byLevel: [String: [AudioExercise]] = [:]
        for ex in exercises {
            byLevel[ex.level, default: []].append(ex)
        }
        var free: Set<String> = []
        for (_, items) in byLevel {
            let firstN = items.prefix(freeItemsPerLevel)
            free.formUnion(firstN.map(\.id))
        }
        return free
    }

    /// Filter helpers — return the input unchanged when fully unlocked.
    static func filterFreeGrammar(_ points: [GrammarPoint]) -> [GrammarPoint] {
        guard !isFullUnlocked else { return points }
        let patternFiles = GrammarLoader.allPatternFiles
        guard let free = freeGrammarIds(from: patternFiles) else { return points }
        return points.filter { free.contains($0.id) }
    }

    static func filterFreeAudio(_ exercises: [AudioExercise]) -> [AudioExercise] {
        guard !isFullUnlocked else { return exercises }
        guard let free = freeAudioIds(from: exercises) else { return exercises }
        return exercises.filter { free.contains($0.id) }
    }

    static func filterFreeExercisePool(_ pool: [String: [SessionExercise]]) -> [String: [SessionExercise]] {
        guard !isFullUnlocked else { return pool }
        guard let free = freeGrammarIds(from: GrammarLoader.allPatternFiles) else { return pool }
        // Particle pool keys aren't grammar IDs; keep entries that aren't grammar-gated.
        // Grammar pool keys match pattern IDs (`n5_001`); particle keys use a different scheme.
        return pool.filter { key, _ in
            if isGrammarPatternID(key) {
                return free.contains(key)
            }
            return true
        }
    }

    /// True if the ID matches the `n[1-5]_NNN` grammar pattern shape used in the
    /// per-pattern JSON files. Particle and audio exercise IDs have extra suffixes
    /// (e.g. `n5_001_1`), so they won't match.
    private static func isGrammarPatternID(_ id: String) -> Bool {
        // Pattern: starts with n1..n5, underscore, exactly 3 digits, nothing after.
        guard id.count == 6 else { return false }
        let chars = Array(id)
        guard chars[0] == "n",
              ["1", "2", "3", "4", "5"].contains(String(chars[1])),
              chars[2] == "_" else { return false }
        return chars[3].isNumber && chars[4].isNumber && chars[5].isNumber
    }
}
