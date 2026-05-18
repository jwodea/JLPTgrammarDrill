import Foundation

/// One audio-eligible exercise bundled with its parent pattern's metadata.
/// Acts as the read-only model the audio drill consumes; equivalent of `SessionExercise`
/// but specific to the audio tab.
struct AudioExercise: Identifiable, Hashable {
    let id: String              // matches Exercise.id, e.g. "n5_001_1"
    let patternId: String       // base pattern id, e.g. "n5_001"
    let pattern: String
    let meaning: String
    let level: String
    let exampleSentence: String
    let translation: String
    let hiraganaFull: String
    let audioAlternatives: [AudioAlternative]
}

enum AudioExerciseLoader {
    /// Returns all audio-eligible exercises in canonical order:
    /// by level (N5 → N1), then by pattern id lexicographically, then by exercise sequence.
    /// Reads from `GrammarLoader.allPatternFiles`, which is parsed once and cached.
    static func loadAll() -> [AudioExercise] {
        let levelOrder = ["N5": 0, "N4": 1, "N3": 2, "N2": 3, "N1": 4]
        let sortedPatterns = GrammarLoader.allPatternFiles.sorted { lhs, rhs in
            let l = levelOrder[lhs.level] ?? 99
            let r = levelOrder[rhs.level] ?? 99
            if l != r { return l < r }
            return lhs.id < rhs.id
        }

        var out: [AudioExercise] = []
        for pf in sortedPatterns {
            for ex in pf.exercises where ex.isAudioEligible {
                guard let hira = ex.hiraganaFull else { continue }
                out.append(AudioExercise(
                    id: ex.id,
                    patternId: pf.id,
                    pattern: pf.pattern,
                    meaning: pf.meaning,
                    level: pf.level,
                    exampleSentence: ex.exampleSentence,
                    translation: ex.translation,
                    hiraganaFull: hira,
                    audioAlternatives: ex.audioAlternatives
                ))
            }
        }
        return out
    }
}
