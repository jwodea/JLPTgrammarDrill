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
    /// `onboardingTarget` total cards, or when no new patterns were asked for
    /// (Review Only, or today's allowance is used up).
    private static func effectiveNewCount(userPreferred: Int, existingTotal: Int) -> Int {
        guard userPreferred > 0, existingTotal < onboardingTarget else { return userPreferred }
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
    /// exercise screen can show their intro cards before the quiz starts.
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

        newItems = introductionOrder(newItems)

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

    /// Sentences for the next unseen pattern in introduction order, skipping
    /// `excluding` (patterns already in the session). Used to swap in a fresh
    /// pattern when the learner marks a new one as already known.
    static func replacementNewPattern(
        allPoints: [GrammarPoint],
        exercisePool: [String: [SessionExercise]],
        context: ModelContext,
        excluding: Set<String>
    ) -> [SessionExercise] {
        let levels = enabledLevels
        let seenIds = Set(((try? context.fetch(FetchDescriptor<SRSRecord>())) ?? []).map(\.grammarId))
        let candidates = allPoints.filter {
            levels.contains($0.level) && !seenIds.contains($0.id) && !excluding.contains($0.id)
        }
        guard let point = introductionOrder(candidates).first else { return [] }
        if let exercises = exercisePool[point.id], !exercises.isEmpty {
            return Array(exercises.shuffled().prefix(3))
        }
        return [fallbackExercise(for: point)]
    }

    // MARK: - Strengthen

    /// Practice for days when nothing is due: the seen patterns FSRS thinks are
    /// most likely to be slipping (lowest current retrievability), skipping any
    /// already studied today. Ratings apply as normal — FSRS handles early
    /// reviews, giving small stability gains on success and pulling a pattern
    /// forward if it's missed.
    static func buildStrengthenSession(
        allPoints: [GrammarPoint],
        exercisePool: [String: [SessionExercise]],
        context: ModelContext,
        limit: Int = 10,
        now: Date = Date()
    ) -> [SessionExercise] {
        let levels = enabledLevels
        let pointsById = Dictionary(
            allPoints.filter { levels.contains($0.level) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let records = try? context.fetch(FetchDescriptor<SRSRecord>()) else { return [] }

        let startOfToday = Calendar.current.startOfDay(for: now)
        let candidates = records.filter { record in
            guard pointsById[record.grammarId] != nil, record.fsrsReps > 0 else { return false }
            if let last = record.lastStudied, last >= startOfToday { return false }
            return true
        }

        let weakest = candidates
            .map { ($0.grammarId, retrievability(of: $0, at: now)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)

        let items: [SessionExercise] = weakest.compactMap { id, _ in
            guard let point = pointsById[id] else { return nil }
            return exercisePool[id]?.randomElement() ?? fallbackExercise(for: point)
        }
        return items.shuffled()
    }

    /// Whether `buildStrengthenSession` would find anything to practice.
    static func canStrengthen(records: [SRSRecord], activeIds: Set<String>, now: Date = Date()) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return records.contains { record in
            guard activeIds.contains(record.grammarId), record.fsrsReps > 0 else { return false }
            return (record.lastStudied ?? .distantPast) < startOfToday
        }
    }

    /// FSRS v5 forgetting curve: R = (1 + F·t/S)^D with D = −0.5, F = 19/81.
    private static func retrievability(of record: SRSRecord, at now: Date) -> Double {
        guard record.fsrsStability > 0, let last = record.fsrsLastReview else { return 0 }
        let elapsedDays = max(0, now.timeIntervalSince(last) / 86_400)
        return pow(1 + (19.0 / 81.0) * elapsedDays / record.fsrsStability, -0.5)
    }

    // MARK: - Ordering

    /// Order unseen patterns for introduction: easiest enabled level first
    /// (N5 before N1), shuffled within each level. The data files keep related
    /// patterns next to each other (several ways to say "not only… but also"),
    /// and introducing those together makes them blur, so file order is avoided.
    /// The shuffle is seeded once per install so the order is stable — the home
    /// screen preview and the session agree, and the queue doesn't reshuffle daily.
    private static func introductionOrder(_ points: [GrammarPoint]) -> [GrammarPoint] {
        let seed = introOrderSeed
        return points
            .map { (point: $0, level: levelOrder($0.level), key: stableHash($0.id, seed: seed)) }
            .sorted { ($0.level, $0.key) < ($1.level, $1.key) }
            .map(\.point)
    }

    private static let introOrderSeedKey = "introOrderSeed"

    private static var introOrderSeed: UInt64 {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: introOrderSeedKey), let seed = UInt64(stored) {
            return seed
        }
        let seed = UInt64.random(in: .min ... .max)
        defaults.set(String(seed), forKey: introOrderSeedKey)
        return seed
    }

    /// FNV-1a over the seed and id. `Hasher` is randomized per launch, so it
    /// can't give an order that stays put across launches.
    private static func stableHash(_ string: String, seed: UInt64) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 ^ seed
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Order a session so new patterns' sentences are spaced out by reviews, rather
    /// than appending each new pattern's sentences back-to-back at the end.
    ///
    /// Layout: round 0 (first sentence of every new pattern mixed with a chunk of
    /// reviews), round 1 (second sentences mixed with the next chunk), and so on.
    /// Reviews are split evenly across the rounds so the gap between repeats of a new
    /// pattern stays roughly constant. Each round is shuffled so the question order
    /// doesn't mirror the order the patterns were introduced in.
    private static func interleave(
        newExercises: [[SessionExercise]],
        reviewExercises: [SessionExercise]
    ) -> [SessionExercise] {
        let rounds = newExercises.map(\.count).max() ?? 0
        guard rounds > 0 else { return reviewExercises }

        var result: [SessionExercise] = []
        var remainingReviews = reviewExercises[...]
        for round in 0..<rounds {
            // Spread what's left evenly over the remaining rounds.
            let chunkSize = Int((Double(remainingReviews.count) / Double(rounds - round)).rounded(.up))
            var chunk = newExercises.compactMap { round < $0.count ? $0[round] : nil }
            chunk.append(contentsOf: remainingReviews.prefix(chunkSize))
            remainingReviews = remainingReviews.dropFirst(chunkSize)
            chunk.shuffle()
            // Patterns are distinct within a round, so one swap stops the same
            // pattern appearing twice in a row across the round boundary.
            if chunk.count > 1, chunk.first?.grammarId == result.last?.grammarId {
                chunk.swapAt(0, 1)
            }
            result.append(contentsOf: chunk)
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
