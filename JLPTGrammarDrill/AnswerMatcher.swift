import Foundation

struct MatchResult {
    let bestScore: Double
    let bestAnswerKanji: String?
    let normalizedRecognition: String
    let passed: Bool
}

enum AnswerMatcher {
    /// Score `recognized` against the exercise's primary form and any audio alternatives.
    /// Returns the best score across all candidate surfaces (kanji + hiragana, primary + alts).
    static func match(recognized: String,
                      exercise: AudioExercise,
                      threshold: Double,
                      stripFinalCopula: Bool) -> MatchResult {
        let normalizedR = TextNormalizer.normalize(recognized, stripFinalCopula: stripFinalCopula)
        let recognizedKanji = kanjiSet(in: recognized)

        var candidates: [(kanji: String, hira: String)] = [
            (exercise.exampleSentence, exercise.hiraganaFull)
        ]
        candidates.append(contentsOf: exercise.audioAlternatives.map { ($0.kanji, $0.hiraganaFull) })

        var bestScore: Double = 0
        var bestKanji: String? = exercise.exampleSentence
        for c in candidates {
            let targetKanji = kanjiSet(in: c.kanji)
            // iOS's kanji choice tracks pronunciation: a mora-level slip often flips the kanji
            // to a different word. Treat a kanji mismatch as evidence of a real pronunciation
            // error, capped so a single STT misfire on clean audio only costs ~10pp.
            let penalty = contentWordPenalty(target: targetKanji, recognized: recognizedKanji)
            for surface in [c.kanji, c.hira] {
                let n = TextNormalizer.normalize(surface, stripFinalCopula: stripFinalCopula)
                let charScore = similarity(normalizedR, n)
                let score = charScore * penalty
                if score > bestScore {
                    bestScore = score
                    bestKanji = c.kanji
                }
            }
        }

        return MatchResult(
            bestScore: bestScore,
            bestAnswerKanji: bestKanji,
            normalizedRecognition: normalizedR,
            passed: bestScore >= threshold
        )
    }

    /// Soft penalty in [0.75, 1.0] driven by how well recognized kanji match the target's kanji.
    /// Returns 1.0 when no content-word check applies (one or both sides have no kanji).
    static func contentWordPenalty(target: Set<Character>, recognized: Set<Character>) -> Double {
        guard !target.isEmpty, !recognized.isEmpty else { return 1.0 }
        let intersection = target.intersection(recognized).count
        let union = target.union(recognized).count
        let jaccard = Double(intersection) / Double(union)
        // 0.25 weight: a fully wrong content-kanji set caps the score at 75% of char similarity,
        // and a single-kanji STT misfire (Jaccard ≈ 0.5–0.67) costs roughly 8–12 percentage points.
        let contentWeight = 0.25
        return (1.0 - contentWeight) + contentWeight * jaccard
    }

    /// Extract the set of CJK ideograph characters from a string.
    static func kanjiSet(in text: String) -> Set<Character> {
        var result: Set<Character> = []
        for ch in text {
            guard let scalar = ch.unicodeScalars.first else { continue }
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0xF900...0xFAFF).contains(v) {
                result.insert(ch)
            }
        }
        return result
    }

    /// Normalized Levenshtein similarity in [0, 1]. 1.0 == identical, 0 == fully different.
    static func similarity(_ a: String, _ b: String) -> Double {
        let ac = Array(a), bc = Array(b)
        let m = ac.count, n = bc.count
        if m == 0 && n == 0 { return 1 }
        if m == 0 || n == 0 { return 0 }
        var prev = Array(0...n)
        var cur = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            cur[0] = i
            for j in 1...n {
                let cost = ac[i - 1] == bc[j - 1] ? 0 : 1
                cur[j] = min(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return 1.0 - Double(prev[n]) / Double(max(m, n))
    }
}
