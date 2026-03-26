import Foundation

class GrammarLoader {

    private static let levelPrefixes = ["n1_", "n2_", "n3_", "n4_", "n5_"]

    /// Load all per-pattern JSON files from the bundle.
    /// Files are named like n1_001.json, n2_050.json, etc.
    private static func loadAllPatternFiles() -> [PatternFile] {
        var all: [PatternFile] = []
        guard let resourceURL = Bundle.main.resourceURL else { return all }

        do {
            let allFiles = try FileManager.default.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: nil
            )
            let patternFiles = allFiles.filter { url in
                guard url.pathExtension == "json" else { return false }
                let name = url.deletingPathExtension().lastPathComponent
                return levelPrefixes.contains(where: { name.hasPrefix($0) })
            }

            for url in patternFiles {
                do {
                    let data = try Data(contentsOf: url)
                    let decoded = try JSONDecoder().decode(PatternFile.self, from: data)
                    all.append(decoded)
                } catch {
                    print("Error loading \(url.lastPathComponent): \(error)")
                }
            }
        } catch {
            print("Error reading bundle resources: \(error)")
        }

        return all.sorted { $0.id < $1.id }
    }

    /// Return one canonical GrammarPoint per base pattern, ordered by base ID.
    /// This is the list used for SRS tracking (one record per grammar pattern).
    static func loadAll() -> [GrammarPoint] {
        let patternFiles = loadAllPatternFiles()
        return patternFiles.map { pf in
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
        let patternFiles = loadAllPatternFiles()
        var pool: [String: [SessionExercise]] = [:]

        for pf in patternFiles {
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
