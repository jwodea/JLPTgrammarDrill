import Foundation
import SwiftData

struct ParticleSessionStats {
    let newCount: Int
    let reviewCount: Int
    let totalDue: Int
}

struct ParticleSessionBuilder {
    static let defaultNewCountKey = "particleDefaultNewPatterns"
    static let defaultNewCount = 3

    /// Preview what the next particle session would look like without modifying the database.
    static func previewSession(allExercises: [ParticleExercise], context: ModelContext, newCount: Int) -> ParticleSessionStats {
        let descriptor = FetchDescriptor<SRSRecord>()
        let existingRecords: [SRSRecord]
        do {
            existingRecords = try context.fetch(descriptor)
        } catch {
            return ParticleSessionStats(newCount: 0, reviewCount: 0, totalDue: 0)
        }

        var recordsByGrammarId: [String: SRSRecord] = [:]
        for record in existingRecords {
            recordsByGrammarId[record.grammarId] = record
        }

        let now = Date()
        var dueCount = 0
        var unseenCount = 0

        for exercise in allExercises {
            if let record = recordsByGrammarId[exercise.id] {
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

        return ParticleSessionStats(newCount: effectiveNew, reviewCount: reviewCount, totalDue: dueCount)
    }

    /// Build a particle session by ranking seen items by how overdue they are, then picking exercises.
    /// `maxItems` caps the total returned items; SRS records are only created for new items
    /// that survive the cap, so particles can't accumulate phantom "introduced" rows that were
    /// dropped before display.
    static func buildSession(
        allExercises: [ParticleExercise],
        context: ModelContext,
        newCount: Int,
        maxItems: Int
    ) -> [SessionExercise] {
        guard maxItems > 0 else { return [] }

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

        var overdueItems: [(exercise: ParticleExercise, overdueBy: TimeInterval)] = []
        var newItems: [ParticleExercise] = []

        for exercise in allExercises {
            if let record = recordsByGrammarId[exercise.id] {
                let overdueBy = now.timeIntervalSince(record.fsrsDue)
                if overdueBy >= 0 {
                    overdueItems.append((exercise, overdueBy))
                }
            } else {
                newItems.append(exercise)
            }
        }

        // Sort by overdue duration descending — most overdue first
        overdueItems.sort { $0.overdueBy > $1.overdueBy }

        // Apply the cap: reviews first, then new items, never exceeding maxItems total.
        let selectedDue = Array(overdueItems.prefix(maxItems).map(\.exercise))
        let remainingSlots = max(0, maxItems - selectedDue.count)
        let selectedNew = Array(newItems.prefix(min(newCount, remainingSlots)))

        // Only now do we create SRS records — guaranteed to match what gets displayed.
        for exercise in selectedNew {
            let newRecord = SRSRecord(grammarId: exercise.id)
            context.insert(newRecord)
        }

        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }

        var sessionExercises: [SessionExercise] = []
        for exercise in selectedDue {
            sessionExercises.append(exercise.toSessionExercise())
        }
        for exercise in selectedNew {
            sessionExercises.append(exercise.toSessionExercise())
        }
        return sessionExercises
    }
}
