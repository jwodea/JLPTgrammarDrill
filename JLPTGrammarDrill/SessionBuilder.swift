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

    /// Onboarding ramp: keep introducing new patterns until the learner has at
    /// least this many cards in their SRS table, capped per session below.
    static let onboardingTarget = 15
    static let onboardingPerSessionCap = 10

    /// Returns the set of JLPT levels the user has enabled in Settings.
    static var enabledLevels: Set<String> {
        let raw = UserDefaults.standard.string(forKey: SettingsView.enabledLevelsKey)
            ?? SettingsView.defaultEnabledLevels
        return Set(raw.split(separator: ",").map(String.init))
    }

    /// Lower JLPT number = harder; sort key returns the numeric portion so
    /// `.sorted(by: <)` on the key yields N5 → N1 (easiest first).
    private static func levelOrder(_ level: String) -> Int {
        let digits = level.compactMap(\.wholeNumberValue)
        let value = digits.reduce(0) { $0 * 10 + $1 }
        return value == 0 ? Int.max : -value
    }

    /// How many new patterns to introduce this session, factoring in the
    /// onboarding ramp. Returns `userPreferred` once the learner is past
    /// `onboardingTarget` total cards.
    private static func effectiveNewCount(userPreferred: Int, existingTotal: Int) -> Int {
        guard existingTotal < onboardingTarget else { return userPreferred }
        let remaining = onboardingTarget - existingTotal
        let ramp = min(onboardingPerSessionCap, remaining)
        return max(userPreferred, ramp)
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
        let rampedNewCount = effectiveNewCount(
            userPreferred: newCount,
            existingTotal: existingRecords.count
        )
        let effectiveNew = min(rampedNewCount, unseenCount)

        return SessionStats(newCount: effectiveNew, reviewCount: reviewCount, totalDue: dueCount)
    }

    /// Build a session by ranking seen items by how overdue they are, then picking exercises.
    /// Also returns the grammar IDs being introduced for the first time so the
    /// exercise screen can show an intro card before each new pattern's first question.
    static func buildSession(
        allPoints: [GrammarPoint],
        exercisePool: [String: [SessionExercise]],
        context: ModelContext,
        newCount: Int
    ) -> (items: [SessionExercise], newPatternIds: Set<String>) {
        let levels = enabledLevels
        let filteredPoints = allPoints.filter { levels.contains($0.level) }

        let descriptor = FetchDescriptor<SRSRecord>()
        let existingRecords: [SRSRecord]
        do {
            existingRecords = try context.fetch(descriptor)
        } catch {
            print("Error fetching SRS records: \(error)")
            return ([], [])
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

        // Introduce patterns from the easiest enabled level first (N5 before N1).
        newItems.sort { levelOrder($0.level) < levelOrder($1.level) }

        let rampedNewCount = effectiveNewCount(
            userPreferred: newCount,
            existingTotal: existingRecords.count
        )
        // No SRS records are created here: ExerciseView inserts them when a pattern is
        // actually answered, so backing out of a session (or switching levels) doesn't
        // leave unstudied patterns behind as phantom "due" reviews.
        let selectedNew = Array(newItems.prefix(rampedNewCount))

        // For review items, pick 1 random exercise per pattern
        let reviewExercises: [SessionExercise] = selectedDue.map { point in
            exercisePool[point.id]?.randomElement() ?? fallbackExercise(for: point)
        }

        // For new patterns, pick 3 shuffled sentences to introduce the pattern
        let introSentenceCount = 3
        let newExercises: [[SessionExercise]] = selectedNew.map { point in
            if let exercises = exercisePool[point.id], !exercises.isEmpty {
                return Array(exercises.shuffled().prefix(introSentenceCount))
            }
            return [fallbackExercise(for: point)]
        }

        let sessionExercises = interleave(newExercises: newExercises, reviewExercises: reviewExercises)
        return (sessionExercises, Set(selectedNew.map(\.id)))
    }

    /// Order a session so new patterns are introduced up front and their follow-up
    /// sentences are spaced out by reviews, rather than appending each new pattern's
    /// sentences back-to-back at the end of the session.
    ///
    /// Layout: round 0 (first sentence of every new pattern), a chunk of reviews,
    /// round 1 (second sentences), another chunk of reviews, and so on. Reviews are
    /// split evenly across the rounds so the gap between repeats of a new pattern
    /// stays roughly constant through the session.
    private static func interleave(
        newExercises: [[SessionExercise]],
        reviewExercises: [SessionExercise]
    ) -> [SessionExercise] {
        let rounds = newExercises.map(\.count).max() ?? 0
        guard rounds > 0 else { return reviewExercises }

        var result: [SessionExercise] = []
        var remainingReviews = reviewExercises[...]
        for round in 0..<rounds {
            result.append(contentsOf: newExercises.compactMap { round < $0.count ? $0[round] : nil })
            // Spread what's left evenly over the remaining rounds.
            let chunkSize = Int((Double(remainingReviews.count) / Double(rounds - round)).rounded(.up))
            result.append(contentsOf: remainingReviews.prefix(chunkSize))
            remainingReviews = remainingReviews.dropFirst(chunkSize)
        }
        return result
    }

    /// Delete SRS records that were created but never rated. Older builds inserted a
    /// record for every new pattern at session start, so abandoned sessions left these
    /// behind; they show up as due reviews even though the learner never studied them.
    @MainActor
    static func removeUnstudiedRecords(context: ModelContext) {
        let descriptor = FetchDescriptor<SRSRecord>(
            predicate: #Predicate { $0.fsrsReps == 0 && $0.totalAttempts == 0 }
        )
        do {
            let unstudied = try context.fetch(descriptor)
            guard !unstudied.isEmpty else { return }
            unstudied.forEach(context.delete)
            try context.save()
        } catch {
            print("Error removing unstudied SRS records: \(error)")
        }
    }

    /// Single exercise built from the grammar point itself, for patterns with no
    /// sentences in the exercise pool.
    private static func fallbackExercise(for point: GrammarPoint) -> SessionExercise {
        SessionExercise(
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
        )
    }
}
