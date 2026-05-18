import Foundation

/// Represents a single particle exercise loaded from the JSON.
struct ParticleExercise: Codable, Identifiable, Hashable {
    let id: String
    let particle: String
    let category: String
    let focus: String
    let exampleSentence: String
    let translation: String
    let blankTarget: String
    let wrongChoices: [String]
    let explanation: String
    let wrongChoiceExplanations: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, particle, category, focus, translation, explanation
        case exampleSentence = "example_sentence"
        case blankTarget = "blank_target"
        case wrongChoices = "wrong_choices"
        case wrongChoiceExplanations = "wrong_choice_explanations"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        particle = try c.decode(String.self, forKey: .particle)
        category = try c.decode(String.self, forKey: .category)
        focus = try c.decode(String.self, forKey: .focus)
        exampleSentence = try c.decode(String.self, forKey: .exampleSentence)
        translation = try c.decode(String.self, forKey: .translation)
        blankTarget = try c.decode(String.self, forKey: .blankTarget)
        wrongChoices = try c.decode([String].self, forKey: .wrongChoices)
        explanation = try c.decode(String.self, forKey: .explanation)
        wrongChoiceExplanations = try c.decodeIfPresent([String: String].self, forKey: .wrongChoiceExplanations) ?? [:]
    }

    /// Returns wrong choice explanations as an ordered array matching wrongChoices order.
    var orderedWrongChoiceExplanations: [String] {
        wrongChoices.map { wrongChoiceExplanations[$0] ?? "" }
    }
}

/// Converts a ParticleExercise into a SessionExercise for use in the shared ExerciseView.
extension ParticleExercise {
    func toSessionExercise() -> SessionExercise {
        SessionExercise(
            id: id,
            grammarId: id,
            pattern: particle,
            meaning: explanation,
            level: "Particles",
            exampleSentence: exampleSentence,
            translation: translation,
            blankTarget: blankTarget,
            wrongChoices: wrongChoices,
            wrongChoiceExplanations: orderedWrongChoiceExplanations
        )
    }
}
