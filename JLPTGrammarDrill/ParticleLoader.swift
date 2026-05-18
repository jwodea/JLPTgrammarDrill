import Foundation

class ParticleLoader {

    /// Load all particle exercises from the bundled JSON file.
    static func loadAll() -> [ParticleExercise] {
        guard let url = Bundle.main.url(forResource: "particles-exercises", withExtension: "json") else {
            print("particles-exercises.json not found in bundle")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let exercises = try JSONDecoder().decode([ParticleExercise].self, from: data)
            return exercises.sorted { $0.id < $1.id }
        } catch {
            print("Error loading particles: \(error)")
            return []
        }
    }

    /// Build a lookup from particle exercise ID to an array containing that exercise as a SessionExercise.
    /// Each particle exercise is its own SRS item (no pattern grouping like grammar).
    static func buildExercisePool() -> [String: [SessionExercise]] {
        let exercises = loadAll()
        var pool: [String: [SessionExercise]] = [:]

        for exercise in exercises {
            let session = exercise.toSessionExercise()
            pool[exercise.id] = [session]
        }

        return pool
    }
}
