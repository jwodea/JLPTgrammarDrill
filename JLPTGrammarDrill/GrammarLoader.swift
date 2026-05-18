import Foundation

class GrammarLoader {

    private static let levelPrefixes = ["n1_", "n2_", "n3_", "n4_", "n5_"]

    /// All per-pattern JSON files (n1_001.json … n5_xxx.json) parsed once on
    /// first access and cached. Bundled resources don't change at runtime, so
    /// every subsequent caller hits this static — no disk I/O, no JSON decode.
    /// `AudioExerciseLoader` reuses the same cache.
    static let allPatternFiles: [PatternFile] = {
        // `urls(forResourcesWithExtension:subdirectory:)` is Apple's recommended
        // bundle-enumeration API — faster than `contentsOfDirectory` and already
        // filtered by extension.
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let patternURLs = urls.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            return levelPrefixes.contains(where: { name.hasPrefix($0) })
        }

        let decoder = JSONDecoder()
        var all: [PatternFile] = []
        all.reserveCapacity(patternURLs.count)
        for url in patternURLs {
            do {
                let data = try Data(contentsOf: url)
                all.append(try decoder.decode(PatternFile.self, from: data))
            } catch {
                print("Error loading \(url.lastPathComponent): \(error)")
            }
        }
        return all.sorted { $0.id < $1.id }
    }()

    /// Return one canonical GrammarPoint per base pattern, ordered by base ID.
    /// This is the list used for SRS tracking (one record per grammar pattern).
    static func loadAll() -> [GrammarPoint] {
        return allPatternFiles.map { pf in
            let first = pf.exercises.first
            return GrammarPoint(
                id: pf.id,
                pattern: pf.pattern,
                meaning: pf.meaning,
                level: pf.level,
                exampleSentence: first?.exampleSentence ?? "",
                translation: first?.translation ?? "",
                blankTarget: first?.blankTarget ?? "",
                wrongChoices: first?.wrongChoices ?? [],
                wrongChoiceExplanations: first?.wrongChoiceExplanations ?? []
            )
        }
    }

    /// Build a lookup from base grammar ID to all available SessionExercises.
    static func buildExercisePool() -> [String: [SessionExercise]] {
        var pool: [String: [SessionExercise]] = [:]

        for pf in allPatternFiles {
            pool[pf.id] = pf.exercises.map { exercise in
                SessionExercise(
                    id: exercise.id,
                    grammarId: pf.id,
                    pattern: pf.pattern,
                    meaning: pf.meaning,
                    level: pf.level,
                    exampleSentence: exercise.exampleSentence,
                    translation: exercise.translation,
                    blankTarget: exercise.blankTarget,
                    wrongChoices: exercise.wrongChoices,
                    wrongChoiceExplanations: exercise.wrongChoiceExplanations
                )
            }
        }

        return pool
    }
}
