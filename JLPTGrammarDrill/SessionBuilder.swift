import Foundation
import SwiftData

struct SessionStats {
    let newCount: Int
    let reviewCount: Int
    let totalDue: Int
}

struct SessionBuilder {
    static let defaultNewCountKey = "defaultNewPatterns"
    static let defaultNewCount = 5

    /// Returns the set of JLPT levels the user has enabled in Settings.
    static var enabledLevels: Set<String> {
        let raw = UserDefaults.standard.string(forKey: SettingsView.enabledLevelsKey)
            ?? SettingsView.defaultEnabledLevels
        return Set(raw.split(separator: ",").map(String.init))
    }

    /// Preview what the next session would look like without modifying the database.
    static func previewSession(allPoints: [GrammarPoint], context: ModelContext, newCount: Int) -> SessionStats {
        let levels = enabledLevels
        let filteredPoints = allPoints.filter { levels.contains($0.level) }

        let descriptor = FetchDescriptor<SRSRecord>()
        let existingRecords: [SRSRecord]
        do {
            existingRecords = try context.fetch(descriptor)
        } catch {
            return SessionStats(newCount: 0, reviewCount: 0, totalDue: 0)
        }

        var recordsByGrammarId: [String: SRSRecord] = [:]
        for record in existingRecords {
            recordsByGrammarId[record.grammarId] = record
        }

        let now = Date()
        var dueCount = 0
        var unseenCount = 0

        for point in filteredPoints {
            if let record = recordsByGrammarId[point.id] {
                if record.fsrsDue <= now {
                    dueCount += 1
                }
            } else {
                unseenCount += 1
            }
        }

        let maxReview = 10
        let reviewCount = min(dueCount, maxReview)
        let effectiveNew = min(newCount, unseenCount)

        return SessionStats(newCount: effectiveNew, reviewCount: reviewCount, totalDue: dueCount)
    }

    /// Build a session by ranking seen items by how overdue they are, then picking exercises.
    static func buildSession(
        allPoints: [GrammarPoint],
        exercisePool: [String: [SessionExercise]],
        context: ModelContext,
        newCount: Int
    ) -> [SessionExercise] {
        let levels = enabledLevels
        let filteredPoints = allPoints.filter { levels.contains($0.level) }

        let descriptor = FetchDescriptor<SRSRecord>()
        let existingRecords: [SRSRecord]
        do {
            existingRecords = try context.fetch(descriptor)
        } catch {
            print("Error fetching SRS records: \(error)")
            return []
        }

        var recordsByGrammarId: [String: SRSRecord] = [:]
        for record in existingRecords {
            recordsByGrammarId[record.grammarId] = record
        }

        let now = Date()

        // Collect seen items sorted by how overdue they are
        var overdueItems: [(point: GrammarPoint, overdueBy: TimeInterval)] = []
        var newItems: [GrammarPoint] = []

        for point in filteredPoints {
            if let record = recordsByGrammarId[point.id] {
                let overdueBy = now.timeIntervalSince(record.fsrsDue)
                // Include items that are due or nearly due (within half their interval)
                if overdueBy >= 0 {
                    overdueItems.append((point, overdueBy))
                }
            } else {
                newItems.append(point)
            }
        }

        // Sort by overdue duration descending — most overdue first
        overdueItems.sort { $0.overdueBy > $1.overdueBy }

        let maxDue = 10
        let selectedDue = overdueItems.prefix(maxDue).map(\.point)

        let selectedNew = Array(newItems.prefix(newCount))

        for point in selectedNew {
            let newRecord = SRSRecord(grammarId: point.id)
            context.insert(newRecord)
        }

        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }

        // For review items, pick 1 random exercise per pattern
        var sessionExercises: [SessionExercise] = []

        for point in selectedDue {
            if let exercises = exercisePool[point.id], let exercise = exercises.randomElement() {
                sessionExercises.append(exercise)
            } else {
                sessionExercises.append(SessionExercise(
                    id: point.id,
                    grammarId: point.id,
                    pattern: point.pattern,
                    meaning: point.meaning,
                    level: point.level,
                    exampleSentence: point.exampleSentence,
                    translation: point.translation,
                    blankTarget: point.blankTarget,
                    wrongChoices: point.wrongChoices,
                    wrongChoiceExplanations: point.wrongChoiceExplanations
                ))
            }
        }

        // For new patterns, pick 3 shuffled sentences to introduce the pattern
        let introSentenceCount = 3
        for point in selectedNew {
            if let exercises = exercisePool[point.id] {
                let picked = Array(exercises.shuffled().prefix(introSentenceCount))
                sessionExercises.append(contentsOf: picked)
            } else {
                sessionExercises.append(SessionExercise(
                    id: point.id,
                    grammarId: point.id,
                    pattern: point.pattern,
                    meaning: point.meaning,
                    level: point.level,
                    exampleSentence: point.exampleSentence,
                    translation: point.translation,
                    blankTarget: point.blankTarget,
                    wrongChoices: point.wrongChoices,
                    wrongChoiceExplanations: point.wrongChoiceExplanations
                ))
            }
        }

        return sessionExercises
    }
}
