import Foundation

class GrammarLoader {

    /// All 30 exercise file names (N1-1 through N3-10).
    private static let fileNames: [String] = {
        var names: [String] = []
        for level in ["N1", "N2", "N3"] {
            for set in 1...10 {
                names.append("\(level)-\(set)")
            }
        }
        return names
    }()

    /// Derive the base grammar-pattern ID from an exercise ID.
    /// e.g. "n3_001_5" → "n3_001",  "n1_100_10" → "n1_100"
    private static func basePatternId(from exerciseId: String) -> String {
        // IDs follow the pattern: <level>_<number>_<set>
        // We want everything up to (but not including) the last underscore.
        if let range = exerciseId.range(of: "_", options: .backwards) {
            return String(exerciseId[..<range.lowerBound])
        }
        return exerciseId
    }

    /// Load every exercise from all 30 JSON files.
    private static func loadAllExercises() -> [GrammarPoint] {
        var all: [GrammarPoint] = []
        for fileName in fileNames {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
                print("Could not find \(fileName).json in bundle")
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(GrammarFile.self, from: data)
                all.append(contentsOf: decoded.grammar)
            } catch {
                print("Error loading \(fileName).json: \(error)")
            }
        }
        return all
    }

    /// Return one canonical GrammarPoint per base pattern, ordered by base ID.
    /// This is the list used for SRS tracking (one record per grammar pattern).
    static func loadAll() -> [GrammarPoint] {
        let allExercises = loadAllExercises()
        var seen: [String: GrammarPoint] = [:]
        var order: [String] = []
        for point in allExercises {
            let base = basePatternId(from: point.id)
            if seen[base] == nil {
                // Keep the first occurrence as the canonical representative
                seen[base] = GrammarPoint(
                    id: base,
                    pattern: point.pattern,
                    meaning: point.meaning,
                    level: point.level,
                    exampleSentence: point.exampleSentence,
                    translation: point.translation,
                    blankTarget: point.blankTarget,
                    wrongChoices: point.wrongChoices,
                    wrongChoiceExplanations: point.wrongChoiceExplanations
                )
                order.append(base)
            }
        }
        return order.compactMap { seen[$0] }
    }

    /// Build a lookup from base grammar ID to all available SessionExercises.
    /// Each pattern will have up to 10 exercise variations drawn from the 30 files.
    static func buildExercisePool() -> [String: [SessionExercise]] {
        let allExercises = loadAllExercises()
        var pool: [String: [SessionExercise]] = [:]

        // First pass: collect pattern metadata keyed by base ID
        var patternMeta: [String: (pattern: String, meaning: String, level: String)] = [:]
        for point in allExercises {
            let base = basePatternId(from: point.id)
            if patternMeta[base] == nil {
                patternMeta[base] = (point.pattern, point.meaning, point.level)
            }
        }

        // Second pass: build SessionExercises
        for point in allExercises {
            let base = basePatternId(from: point.id)
            guard let meta = patternMeta[base] else { continue }
            let sessionEx = SessionExercise(
                id: point.id,
                grammarId: base,
                pattern: meta.pattern,
                meaning: meta.meaning,
                level: meta.level,
                exampleSentence: point.exampleSentence,
                translation: point.translation,
                blankTarget: point.blankTarget,
                wrongChoices: point.wrongChoices,
                wrongChoiceExplanations: point.wrongChoiceExplanations
            )
            pool[base, default: []].append(sessionEx)
        }

        return pool
    }
}
