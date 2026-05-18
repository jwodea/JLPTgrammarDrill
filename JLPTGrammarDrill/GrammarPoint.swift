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

    enum CodingKeys: String, CodingKey {
        case id, translation
        case exampleSentence = "example_sentence"
        case blankTarget = "blank_target"
        case wrongChoices = "wrong_choices"
        case wrongChoiceExplanations = "wrong_choice_explanations"
        case hiraganaFull = "hiragana_full"
        case audioAlternatives = "audio_alternatives"
        case audioEligible = "audio_eligible"
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
}
