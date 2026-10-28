import Foundation

/// Represents a per-pattern JSON file containing all exercises for one grammar pattern.
struct PatternFile: Codable {
    let id: String
    let pattern: String
    let meaning: String
    let level: String
    let exercises: [Exercise]
}

/// One alternative spoken form for an exercise, used by the audio drill.
struct AudioAlternative: Codable, Hashable {
    let kanji: String
    let hiraganaFull: String

    enum CodingKeys: String, CodingKey {
        case kanji
        case hiraganaFull = "hiragana_full"
    }
}

/// A significant vocabulary word appearing in an exercise sentence.
/// Optional enrichment field — surfaced as tappable chips on the drill screen.
struct VocabItem: Codable, Hashable {
    let word: String
    let reading: String
    let meaning: String
}

/// A single exercise variation within a grammar pattern file.
struct Exercise: Codable {
    let id: String
    let exampleSentence: String
    let translation: String
    let blankTarget: String
    let wrongChoices: [String]
    let wrongChoiceExplanations: [String]

    // Audio drill — optional fields added in the JSON migration. Grammar/particle tabs ignore them.
    let hiraganaFull: String?
    let audioAlternatives: [AudioAlternative]
    let audioEligible: Bool

    // Enrichment — optional fields; absent in un-enriched files, features stay hidden.
    let vocab: [VocabItem]
    let blankTargetReading: String?
    /// 1-based occurrence of `blankTarget` to blank when it appears more than once in the
    /// sentence (e.g. し in 面白いし、…勉強しています). Absent = blank every occurrence,
    /// which is what paired patterns (〜といい〜といい, 〜とか〜とか) want.
    let blankOccurrence: Int?

    enum CodingKeys: String, CodingKey {
        case id, translation, vocab
        case exampleSentence = "example_sentence"
        case blankTarget = "blank_target"
        case wrongChoices = "wrong_choices"
        case wrongChoiceExplanations = "wrong_choice_explanations"
        case hiraganaFull = "hiragana_full"
        case audioAlternatives = "audio_alternatives"
        case audioEligible = "audio_eligible"
        case blankTargetReading = "blank_target_reading"
        case blankOccurrence = "blank_occurrence"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        exampleSentence = try container.decode(String.self, forKey: .exampleSentence)
        translation = try container.decode(String.self, forKey: .translation)
        blankTarget = try container.decode(String.self, forKey: .blankTarget)
        wrongChoices = try container.decode([String].self, forKey: .wrongChoices)
        wrongChoiceExplanations = try container.decodeIfPresent([String].self, forKey: .wrongChoiceExplanations) ?? []
        hiraganaFull = try container.decodeIfPresent(String.self, forKey: .hiraganaFull)
        audioAlternatives = try container.decodeIfPresent([AudioAlternative].self, forKey: .audioAlternatives) ?? []
        audioEligible = try container.decodeIfPresent(Bool.self, forKey: .audioEligible) ?? true
        vocab = try container.decodeIfPresent([VocabItem].self, forKey: .vocab) ?? []
        blankTargetReading = try container.decodeIfPresent(String.self, forKey: .blankTargetReading)
        blankOccurrence = try container.decodeIfPresent(Int.self, forKey: .blankOccurrence)
    }

    /// True iff this exercise has audio data and is not opted out.
    var isAudioEligible: Bool {
        audioEligible && !(hiraganaFull?.isEmpty ?? true)
    }
}

struct GrammarPoint: Codable, Identifiable, Hashable {
    let id: String
    let pattern: String
    let meaning: String
    let level: String
    let exampleSentence: String
    let translation: String
    let blankTarget: String
    let wrongChoices: [String]
    let wrongChoiceExplanations: [String]

    enum CodingKeys: String, CodingKey {
        case id, pattern, meaning, level, translation
        case exampleSentence = "example_sentence"
        case blankTarget = "blank_target"
        case wrongChoices = "wrong_choices"
        case wrongChoiceExplanations = "wrong_choice_explanations"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        pattern = try container.decode(String.self, forKey: .pattern)
        meaning = try container.decode(String.self, forKey: .meaning)
        level = try container.decode(String.self, forKey: .level)
        exampleSentence = try container.decode(String.self, forKey: .exampleSentence)
        translation = try container.decode(String.self, forKey: .translation)
        blankTarget = try container.decode(String.self, forKey: .blankTarget)
        wrongChoices = try container.decode([String].self, forKey: .wrongChoices)
        wrongChoiceExplanations = try container.decodeIfPresent([String].self, forKey: .wrongChoiceExplanations) ?? []
    }

    init(id: String, pattern: String, meaning: String, level: String, exampleSentence: String, translation: String, blankTarget: String, wrongChoices: [String], wrongChoiceExplanations: [String] = []) {
        self.id = id
        self.pattern = pattern
        self.meaning = meaning
        self.level = level
        self.exampleSentence = exampleSentence
        self.translation = translation
        self.blankTarget = blankTarget
        self.wrongChoices = wrongChoices
        self.wrongChoiceExplanations = wrongChoiceExplanations
    }
}

/// A fully resolved exercise ready for use in a session.
/// Combines exercise-level data (sentence, answers) with pattern-level data (pattern name, meaning)
/// needed for the explanation card and SRS tracking.
struct SessionExercise: Identifiable, Hashable {
    let id: String
    let grammarId: String
    let pattern: String
    let meaning: String
    let level: String
    let exampleSentence: String
    let translation: String
    let blankTarget: String
    let wrongChoices: [String]
    let wrongChoiceExplanations: [String]
    let vocab: [VocabItem]
    let blankTargetReading: String?
    let blankOccurrence: Int?

    init(
        id: String,
        grammarId: String,
        pattern: String,
        meaning: String,
        level: String,
        exampleSentence: String,
        translation: String,
        blankTarget: String,
        wrongChoices: [String],
        wrongChoiceExplanations: [String],
        vocab: [VocabItem] = [],
        blankTargetReading: String? = nil,
        blankOccurrence: Int? = nil
    ) {
        self.id = id
        self.grammarId = grammarId
        self.pattern = pattern
        self.meaning = meaning
        self.level = level
        self.exampleSentence = exampleSentence
        self.translation = translation
        self.blankTarget = blankTarget
        self.wrongChoices = wrongChoices
        self.wrongChoiceExplanations = wrongChoiceExplanations
        self.vocab = vocab
        self.blankTargetReading = blankTargetReading
        self.blankOccurrence = blankOccurrence
    }

    /// Range of the blanked occurrence of `blankTarget` (the `blankOccurrence`-th, else the first).
    var blankRange: Range<String.Index>? {
        exampleSentence.rangeOfOccurrence(of: blankTarget, occurrence: blankOccurrence ?? 1)
    }

    /// The sentence with the target replaced by `blank` — only the chosen occurrence when
    /// `blankOccurrence` is set, otherwise every occurrence.
    func blanked(with blank: String) -> String {
        guard let n = blankOccurrence,
              let r = exampleSentence.rangeOfOccurrence(of: blankTarget, occurrence: n) else {
            return exampleSentence.replacingOccurrences(of: blankTarget, with: blank)
        }
        return exampleSentence.replacingCharacters(in: r, with: blank)
    }
}

extension String {
    /// Range of the n-th (1-based) non-overlapping occurrence of `target`, or nil.
    func rangeOfOccurrence(of target: String, occurrence n: Int) -> Range<String.Index>? {
        guard n >= 1, !target.isEmpty else { return nil }
        var searchStart = startIndex
        var count = 0
        while let r = range(of: target, range: searchStart..<endIndex) {
            count += 1
            if count == n { return r }
            searchStart = r.upperBound
        }
        return nil
    }
}
