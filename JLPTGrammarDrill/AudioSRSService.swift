import Foundation
import SwiftData
import SwiftFSRS

/// One item in the upcoming drill queue.
enum AudioQueueItem: Identifiable, Hashable {
    case review(AudioCard, AudioExercise)
    case new(AudioExercise)

    var exercise: AudioExercise {
        switch self {
        case .review(_, let ex): return ex
        case .new(let ex): return ex
        }
    }

    var card: AudioCard? {
        switch self {
        case .review(let c, _): return c
        case .new: return nil
        }
    }

    var id: String { exercise.id }
}

/// Manages FSRS state plus Ringotan-style new-card introduction for the audio drill.
@MainActor
final class AudioSRSService {
    let context: ModelContext
    private let allExercises: [AudioExercise]
    private let exerciseById: [String: AudioExercise]

    init(context: ModelContext, allExercises: [AudioExercise]) {
        self.context = context
        self.allExercises = allExercises
        self.exerciseById = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })
    }

    // MARK: - Queue building

    /// Build the drill queue: due reviews first, with a budgeted set of new cards interleaved.
    func buildQueue(activeLevels: Set<String>,
                    dailyNewCardBudget: Int,
                    learningPoolCap: Int,
                    now: Date = .now) -> [AudioQueueItem] {
        let eligibleIds = Set(allExercises.filter { activeLevels.contains($0.level) }.map(\.id))

        // 1. Gather due cards for eligible exercises.
        let cards = (try? context.fetch(FetchDescriptor<AudioCard>())) ?? []
        let dueCards = cards
            .filter { eligibleIds.contains($0.exerciseId) && $0.fsrsDue <= now }
            .sorted { $0.fsrsDue < $1.fsrsDue }

        let reviewItems: [AudioQueueItem] = dueCards.compactMap { card in
            guard let ex = exerciseById[card.exerciseId] else { return nil }
            return .review(card, ex)
        }

        // 2. Compute new-card slots.
        var slots = max(0, dailyNewCardBudget - introducedTodayCount(cards: cards, now: now))
        if learningPoolCount(cards: cards, activeLevels: activeLevels) >= learningPoolCap {
            slots = 0
        }

        // 3. Pick new exercises in canonical order (allExercises is already sorted).
        let cardedIds = Set(cards.map(\.exerciseId))
        let newExercises = allExercises
            .filter { activeLevels.contains($0.level) && !cardedIds.contains($0.id) }
            .prefix(slots)
        let newItems: [AudioQueueItem] = newExercises.map { .new($0) }

        // 4. Interleave: one new after every 4 reviews; if no reviews, all new first.
        if reviewItems.isEmpty {
            return newItems
        }
        var result: [AudioQueueItem] = []
        var newIdx = 0
        for (i, item) in reviewItems.enumerated() {
            result.append(item)
            if (i + 1) % 4 == 0, newIdx < newItems.count {
                result.append(newItems[newIdx])
                newIdx += 1
            }
        }
        while newIdx < newItems.count {
            result.append(newItems[newIdx])
            newIdx += 1
        }
        return result
    }

    // MARK: - Card lifecycle

    /// Fetch or lazily create an AudioCard for an exercise. Does NOT touch `introducedAt` —
    /// callers must invoke `markIntroduced(_:)` separately when the card actually enters
    /// the learning pool. This keeps the Too-easy path from burning the daily new-card budget.
    @discardableResult
    func ensureCard(for exercise: AudioExercise) -> AudioCard {
        if let existing = fetchCard(exerciseId: exercise.id) {
            return existing
        }
        let card = AudioCard(exerciseId: exercise.id)
        context.insert(card)
        try? context.save()
        return card
    }

    /// Stamp `introducedAt` if it isn't set yet. Call this only when the card is being
    /// added to the active learning pool (i.e. the first real recording attempt).
    func markIntroduced(card: AudioCard, now: Date = .now) {
        guard card.introducedAt == nil else { return }
        card.introducedAt = now
        try? context.save()
    }

    /// Apply an FSRS rating to a card.
    func grade(card: AudioCard, rating: Rating, now: Date = .now) {
        let review = fsrsScheduler.schedule(
            card: card.fsrsCard,
            algorithm: FSRSAlgorithm.v5,
            reviewRating: rating,
            reviewTime: now
        )
        card.update(from: review.postReviewCard)
        try? context.save()
    }

    /// Graduate an exercise as "too easy" without recording. Schedules at FSRS Easy.
    /// Intentionally does NOT set `introducedAt`, so it doesn't count against today's
    /// new-card budget.
    func markTooEasy(exercise: AudioExercise, now: Date = .now) -> AudioCard {
        let card = ensureCard(for: exercise)
        grade(card: card, rating: .easy, now: now)
        return card
    }

    /// Build a queue of N new exercises regardless of today's budget or pool cap.
    /// Used by the "drill more" override on the home view.
    func extraNewQueue(activeLevels: Set<String>, count: Int) -> [AudioQueueItem] {
        let cards = (try? context.fetch(FetchDescriptor<AudioCard>())) ?? []
        let cardedIds = Set(cards.map(\.exerciseId))
        return allExercises
            .filter { activeLevels.contains($0.level) && !cardedIds.contains($0.id) }
            .prefix(count)
            .map { .new($0) }
    }

    // MARK: - Counts

    func dueCount(activeLevels: Set<String>, now: Date = .now) -> Int {
        let cards = (try? context.fetch(FetchDescriptor<AudioCard>())) ?? []
        return dueCount(cards: cards, activeLevels: activeLevels, now: now)
    }

    func learningPoolCount(activeLevels: Set<String>) -> Int {
        let cards = (try? context.fetch(FetchDescriptor<AudioCard>())) ?? []
        return learningPoolCount(cards: cards, activeLevels: activeLevels)
    }

    func introducedTodayCount(now: Date = .now) -> Int {
        let cards = (try? context.fetch(FetchDescriptor<AudioCard>())) ?? []
        return introducedTodayCount(cards: cards, now: now)
    }

    // MARK: - Pre-fetched variants
    // Callers that already hold an `[AudioCard]` (e.g. via `@Query`) can use
    // these directly to avoid re-fetching the whole table per count.

    func dueCount(cards: [AudioCard], activeLevels: Set<String>, now: Date = .now) -> Int {
        let eligibleIds = Set(allExercises.filter { activeLevels.contains($0.level) }.map(\.id))
        return cards.filter { eligibleIds.contains($0.exerciseId) && $0.fsrsDue <= now }.count
    }

    func learningPoolCount(cards: [AudioCard], activeLevels: Set<String>) -> Int {
        let eligibleIds = Set(allExercises.filter { activeLevels.contains($0.level) }.map(\.id))
        return cards.filter { eligibleIds.contains($0.exerciseId) && $0.isInLearningPool }.count
    }

    func introducedTodayCount(cards: [AudioCard], now: Date = .now) -> Int {
        let cal = Calendar.current
        return cards.filter { card in
            guard let intro = card.introducedAt else { return false }
            return cal.isDate(intro, inSameDayAs: now)
        }.count
    }

    func availableNewCount(activeLevels: Set<String>) -> Int {
        let cards = (try? context.fetch(FetchDescriptor<AudioCard>())) ?? []
        let cardedIds = Set(cards.map(\.exerciseId))
        return allExercises.filter { activeLevels.contains($0.level) && !cardedIds.contains($0.id) }.count
    }

    /// Delete all AudioCard rows.
    func resetAllProgress() {
        try? context.delete(model: AudioCard.self)
        try? context.save()
    }

    // MARK: - Private helpers

    private func fetchCard(exerciseId: String) -> AudioCard? {
        let descriptor = FetchDescriptor<AudioCard>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try? context.fetch(descriptor).first
    }
}
