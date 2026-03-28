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

    enum CodingKeys: String, CodingKey {
        case id, particle, category, focus, translation, explanation
        case exampleSentence = "example_sentence"
        case blankTarget = "blank_target"
        case wrongChoices = "wrong_choices"
    }
}

/// Converts a ParticleExercise into a SessionExercise for use in the shared ExerciseView.
extension ParticleExercise {
    func toSessionExercise() -> SessionExercise {
        SessionExercise(
            id: id,
            grammarId: id,       // Each particle exercise is its own SRS item
            pattern: particle,   // The particle itself (が、を、に etc.)
            meaning: explanation, // Use explanation as the "meaning" shown in the card
            level: "Particles",
            exampleSentence: exampleSentence,
            translation: translation,
            blankTarget: blankTarget,
            wrongChoices: wrongChoices,
            wrongChoiceExplanations: [] // Particle exercises use a single explanation field
        )
    }
}
