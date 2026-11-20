import SwiftUI
import SwiftData
import SwiftFSRS
import CoreText
import AVFoundation

/// Aggregated outcomes for one grammar pattern across a single session.
/// Grammar patterns are spread over many sentences but represent a single FSRS card,
/// so we collect every on-screen answer here and emit one `applyRating` call at end
/// of session — see `flushPatternRatings()`.
private struct PatternOutcomes {
    /// First-attempt correct/wrong per distinct SessionExercise.id. Retries don't
    /// overwrite the original result, so this stays faithful to the user's real
    /// first-try performance.
    var firstAttempts: [String: Bool] = [:]
    /// Every answer the user gave, including retries — feeds totalAttempts / totalCorrect
    /// so the local accuracy stat keeps matching what was on screen.
    var totalAnswers = 0
    var correctAnswers = 0
}

struct ExerciseView: View {
    let sessionItems: [SessionExercise]
    let exercisePool: [String: [SessionExercise]]
    /// Grammar IDs being introduced for the first time this session. Their intro
    /// cards (pattern, meaning, examples) are all shown up front, before the quiz.
    var newPatternIds: Set<String> = []
    /// Work left today (due reviews, new patterns still in today's plan) after this
    /// session's ratings are flushed. Shown on the end-of-session summary to decide
    /// whether to offer "Keep Going".
    var remainingWork: (() -> (due: Int, new: Int))? = nil
    /// Builds the follow-up session so "Keep Going" can restart in place instead of
    /// bouncing back to Home and pushing a new screen.
    var buildNextSession: (() -> (items: [SessionExercise], newPatternIds: Set<String>))? = nil
    /// Sentences for a fresh unseen pattern (skipping the given IDs), swapped in when
    /// the learner marks a new pattern as already known. Empty when none are left.
    var replacementNewPattern: ((Set<String>) -> [SessionExercise])? = nil
    @Environment(\.modelContext) private var modelContext
    @Query private var srsRecords: [SRSRecord]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    // Queue of exercises still to present
    @State private var queue: [SessionExercise] = []
    // Consecutive correct answers per grammar pattern (need 3 to finish)
    @State private var streaks: [String: Int] = [:]
    // Set of grammar IDs that have reached 3 consecutive correct
    @State private var completedPatterns: Set<String> = []
    // Ordered list of distinct grammar IDs for progress bar segments
    @State private var orderedPatternIds: [String] = []
    // Total distinct patterns in this session
    @State private var totalPatterns = 0
    // Patterns that have had at least one wrong answer (used for color logic)
    @State private var failedPatterns: Set<String> = []
    @State private var questionsAnswered = 0

    @State private var selectedAnswer: String?
    @State private var showingResult = false
    @State private var shuffledChoices: [String] = []
    @State private var showExplanation = false
    // Wrong choice whose "why it's wrong" popover is open (tapped after answering).
    @State private var explainedChoice: String?
    // Per-pattern required streak. Particles only need 1 correct retry; grammar needs 3.
    @State private var requiredStreaks: [String: Int] = [:]
    // Per-pattern aggregated outcomes — drives a single FSRS rating per pattern at end of session.
    @State private var patternOutcomes: [String: PatternOutcomes] = [:]
    // Guards against flushing twice when both `advanceToNext` and `onDisappear` fire.
    @State private var didFlushRatings = false
    // Intro cards still to show, one per new pattern. The quiz starts once it's empty.
    @State private var introQueue: [SessionExercise] = []
    @State private var introTotal = 0
    // Starts as `newPatternIds`; replaced when "Keep Going" loads the next session.
    @State private var activeNewPatternIds: Set<String> = []
    @State private var didInitialize = false
    // End-of-session summary, shown in place of the question once the session finishes.
    @State private var showSummary = false
    @State private var summaryDueCount = 0
    @State private var summaryNewCount = 0
    // Reads the completed sentence aloud from the revealed explanation card.
    @State private var speaker = JapaneseSpeaker()

    private let defaultRequiredStreak = 3
    private let particleRequiredStreak = 1

    private func requiredStreak(for grammarId: String) -> Int {
        requiredStreaks[grammarId] ?? defaultRequiredStreak
    }

    private var currentItem: SessionExercise? {
        queue.first
    }

    private var isSessionComplete: Bool {
        completedPatterns.count >= totalPatterns && totalPatterns > 0
    }

    private var blankedSentence: String {
        guard let item = currentItem else { return "" }
        let blank = "＿＿＿＿"
        if item.exampleSentence.range(of: "_{2,}", options: .regularExpression) != nil {
            return item.exampleSentence.replacingOccurrences(
                of: "_{2,}",
                with: blank,
                options: .regularExpression
            )
        }
        return item.blanked(with: blank)
    }

    private var filledSentence: String {
        guard let item = currentItem else { return "" }
        if item.exampleSentence.range(of: "_{2,}", options: .regularExpression) != nil {
            return item.exampleSentence.replacingOccurrences(
                of: "_{2,}",
                with: item.blankTarget,
                options: .regularExpression
            )
        }
        return item.exampleSentence
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    /// Furigana for the revealed answer: only when a reading exists and actually
    /// differs from the target (kana-only targets need no ruby).
    private var targetRuby: (base: String, reading: String)? {
        guard let item = currentItem,
              let reading = item.blankTargetReading,
              !reading.isEmpty,
              reading != item.blankTarget else { return nil }
        return (item.blankTarget, reading)
    }

    // MARK: - Mastery Indicator

    /// Small icon for the pattern's current mastery bucket, using the same
    /// thresholds and icons as the Grammar Browser and Stats card. Ratings are
    /// flushed at session end, so this reflects mastery as of session start.
    private func masteryIcon(for grammarId: String) -> some View {
        let (icon, color, label): (String, Color, String) = {
            guard let record = srsRecords.first(where: { $0.grammarId == grammarId }) else {
                return ("sparkles", .secondary, "Unseen")
            }
            switch record.fsrsScheduledDays {
            case 60...: return ("crown", .yellow, "Mastered")
            case 14...: return ("star", .purple, "Confident")
            case 3...: return ("book.closed", .blue, "Familiar")
            default: return ("flame", .orange, "Learning")
            }
        }()
        return Image(systemName: icon)
            .font(.system(size: scaled(12), weight: .semibold))
            .foregroundStyle(color.opacity(0.7))
            .accessibilityLabel("Mastery: \(label)")
    }

    var body: some View {
        ZStack {
            TactileBackdrop().ignoresSafeArea()

            if showSummary {
                ScrollView {
                    SessionSummaryCard(
                        patternCount: totalPatterns,
                        questionsAnswered: questionsAnswered,
                        firstTryAccuracy: firstTryAccuracy,
                        remainingDue: summaryDueCount,
                        remainingNew: summaryNewCount,
                        canKeepReviewing: buildNextSession != nil,
                        onKeepReviewing: keepReviewing,
                        onDone: { dismiss() }
                    )
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                }
                .transition(.opacity)
            } else if let item = currentItem {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            // Segmented progress bar
                            VStack(spacing: 6) {
                                SessionProgressBar(
                                    orderedPatternIds: orderedPatternIds,
                                    streaks: streaks,
                                    completedPatterns: completedPatterns,
                                    failedPatterns: failedPatterns,
                                    requiredStreaks: requiredStreaks,
                                    defaultRequiredStreak: defaultRequiredStreak
                                )
                                .frame(height: 8)
                                .padding(.horizontal)

                                Text("\(completedPatterns.count)/\(totalPatterns) finished")
                                    .font(.system(size: scaled(12), weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            .padding(.top)

                            if let introItem = introQueue.first {
                                PatternIntroCard(
                                    item: introItem,
                                    examples: introExamples(for: introItem),
                                    position: introTotal - introQueue.count + 1,
                                    total: introTotal,
                                    onMarkKnown: { markKnown(introItem.grammarId) }
                                ) {
                                    // Only dismiss if this card is still the front one, so a
                                    // double-tap during the transition can't skip a card or
                                    // remove from an empty queue.
                                    guard introQueue.first?.grammarId == introItem.grammarId else { return }
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        _ = introQueue.removeFirst()
                                    }
                                }
                                .id(introItem.grammarId)
                                .padding(.top, 20)
                            } else {
                                questionContent(for: item)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .onChange(of: showExplanation) {
                        if showExplanation {
                            withAnimation {
                                proxy.scrollTo("explanation", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Pinned so "Next" is always in the same spot, regardless of how long the
            // sentence and explanation are.
            if showExplanation && !showSummary {
                Button {
                    advanceToNext()
                } label: {
                    HStack(spacing: 8) {
                        Text(isSessionComplete ? "All Done" : "Next")
                        Image(systemName: isSessionComplete ? "checkmark" : "arrow.right")
                    }
                    .font(.system(size: scaled(17), weight: .bold))
                }
                .buttonStyle(TactilePrimaryButtonStyle())
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(
                    Theme.canvas
                        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
                        .ignoresSafeArea()
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    flushPatternRatings()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            if !showSummary, let grammarId = introQueue.first?.grammarId ?? currentItem?.grammarId {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            markKnown(grammarId)
                        } label: {
                            Label("Mark Pattern as Known", systemImage: "checkmark.seal")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
        .onAppear {
            // onAppear can re-fire (e.g. after a popover); only set up the first time so
            // an in-progress or "Keep Reviewing" session isn't reset to the original items.
            guard !didInitialize else { return }
            didInitialize = true
            initializeSession(items: sessionItems, newPatternIds: newPatternIds)
        }
        .onDisappear {
            // Safety net for any dismissal path (system gesture, etc.) that
            // skips both the X button and `advanceToNext`. The flush is idempotent.
            speaker.stop()
            flushPatternRatings()
        }
    }

    // MARK: - Question Content

    /// The quiz UI for the current item: sentence, answer grid, vocab chips, explanation card.
    @ViewBuilder
    private func questionContent(for item: SessionExercise) -> some View {
        // Question card
        VStack(alignment: .leading, spacing: 12) {
            SelectableText(
                text: blankedSentence,
                fontSize: scaled(24),
                fontWeight: .bold,
                textColor: Theme.inkUIColor,
                textAlignment: .left
            )

            SelectableText(
                text: item.translation,
                fontSize: scaled(16),
                fontWeight: .regular,
                textColor: Theme.inkMutedUIColor,
                textAlignment: .left
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        // Tucked into the card's corner padding so it takes no layout space.
        .overlay(alignment: .topTrailing) {
            masteryIcon(for: item.grammarId)
                .padding(8)
        }
        .tactileCard()
        .padding(.horizontal)
        .padding(.top, 8)

        // Answer buttons (2x2 grid)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 12) {
            ForEach(shuffledChoices, id: \.self) { choice in
                // The selected wrong answer is already explained in the card below.
                let explanation = choice == selectedAnswer ? nil : wrongChoiceExplanation(for: choice, in: item)
                Button {
                    if selectedAnswer == nil {
                        handleAnswer(choice, for: item)
                    } else if explanation != nil {
                        // After answering, wrong tiles can be tapped to see why they're wrong.
                        explainedChoice = choice
                    }
                } label: {
                    Text(choice)
                        .font(.system(size: scaled(18), weight: .semibold))
                        .strikethrough(answerState(for: choice) == .wrong, color: Theme.incorrect)
                }
                .buttonStyle(AnswerTileButtonStyle(state: answerState(for: choice)))
                .disabled(selectedAnswer != nil && explanation == nil)
                .animation(.easeInOut(duration: 0.2), value: selectedAnswer)
                .popover(
                    isPresented: Binding(
                        get: { explainedChoice == choice },
                        set: { if !$0 { explainedChoice = nil } }
                    ),
                    arrowEdge: .bottom
                ) {
                    if let explanation {
                        VStack(alignment: .leading, spacing: 6) {
                            (Text(choice).foregroundStyle(Theme.incorrect)
                             + Text("  vs  ").foregroundStyle(Theme.inkMuted)
                             + Text(item.blankTarget).foregroundStyle(Theme.correct))
                                .font(.system(size: scaled(15), weight: .bold))
                            Text(explanation)
                                .font(.system(size: scaled(15)))
                                .foregroundStyle(Theme.ink)
                        }
                        // Fixed width + ideal height so the popover grows to fit long
                        // explanations instead of truncating them.
                        .frame(width: 290, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
        .padding(.horizontal)

        // Significant-vocab chips — tap for reading + meaning
        if !item.vocab.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("SENTENCE VOCABULARY")
                    .font(.system(size: scaled(11), weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Theme.inkMuted)
                ChipFlowLayout(spacing: 8) {
                    ForEach(item.vocab, id: \.self) { vocabItem in
                        VocabChip(item: vocabItem, fontSize: scaled(19))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
        }

        // Explanation card
        if showExplanation {
            VStack(alignment: .leading, spacing: 10) {
                // Show why the selected wrong answer is wrong
                if let selected = selectedAnswer,
                   selected != item.blankTarget,
                   let idx = item.wrongChoices.firstIndex(of: selected),
                   idx < item.wrongChoiceExplanations.count {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("NUANCE")
                                .font(.system(size: scaled(10), weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(Theme.amber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Theme.amberTint)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Theme.amberBorder, lineWidth: 1)
                                )
                            (Text(item.blankTarget).foregroundStyle(Theme.correct)
                             + Text("  vs  ").foregroundStyle(Theme.inkMuted)
                             + Text(selected).foregroundStyle(Theme.incorrect))
                                .font(.system(size: scaled(14), weight: .bold))
                        }
                        Text(item.wrongChoiceExplanations[idx])
                            .font(.system(size: scaled(15)))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.slateTint)
                    )
                    .padding(.bottom, 4)
                }

                Text(item.pattern)
                    .font(.system(size: scaled(19), weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text(item.meaning)
                    .font(.system(size: scaled(16)))
                    .foregroundStyle(Theme.inkMuted)

                // Inline speaker icon after the 。 reads the sentence aloud.
                SelectableText(
                    text: filledSentence,
                    fontSize: scaled(17),
                    fontWeight: .regular,
                    textColor: Theme.inkUIColor,
                    textAlignment: .left,
                    rubyBase: targetRuby?.base,
                    rubyReading: targetRuby?.reading,
                    onSpeak: { speaker.speak(filledSentence, rate: AVSpeechUtteranceDefaultSpeechRate) }
                )

                SelectableText(
                    text: item.translation,
                    fontSize: scaled(15),
                    fontWeight: .regular,
                    textColor: Theme.inkMutedUIColor,
                    textAlignment: .left
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tactileCard(cornerRadius: 20)
            .padding(.horizontal)
            .transition(.move(edge: .bottom))
            .id("explanation")
        }
    }

    // MARK: - New Pattern Introduction

    /// Example sentences for the intro card, drawn from the pattern's full pool
    /// so the learner sees the pattern in context before being quizzed on it.
    /// Prefers sentences that aren't queued as questions, so the quiz doesn't
    /// replay an answer the learner was just shown.
    private func introExamples(for item: SessionExercise) -> [SessionExercise] {
        let pool = exercisePool[item.grammarId] ?? []
        guard !pool.isEmpty else { return [item] }
        let queuedIds = Set(queue.map(\.id))
        let unqueued = pool.filter { !queuedIds.contains($0.id) }
        let queued = pool.filter { queuedIds.contains($0.id) }
        return Array((unqueued + queued).prefix(2))
    }

    /// One intro item per new pattern. Shuffled so the intro order doesn't predict
    /// the question order, and the last pattern introduced isn't the first question.
    private func buildIntroQueue(items: [SessionExercise], newPatternIds: Set<String>) -> [SessionExercise] {
        var seen = Set<String>()
        var intros = items.filter { newPatternIds.contains($0.grammarId) && seen.insert($0.grammarId).inserted }
        intros.shuffle()
        if intros.count > 1, intros.last?.grammarId == items.first?.grammarId {
            intros.swapAt(0, intros.count - 1)
        }
        return intros
    }

    // MARK: - Session Initialization

    /// Reset all per-session state and load `items`. Used for the initial session and
    /// again for each "Keep Reviewing" round.
    private func initializeSession(items: [SessionExercise], newPatternIds: Set<String>) {
        streaks = [:]
        completedPatterns = []
        failedPatterns = []
        requiredStreaks = [:]
        patternOutcomes = [:]
        questionsAnswered = 0
        selectedAnswer = nil
        showingResult = false
        showExplanation = false
        didFlushRatings = false
        activeNewPatternIds = newPatternIds

        // Collect unique grammar pattern IDs in order
        var seenPatterns = Set<String>()
        var ordered: [String] = []
        for item in items {
            if seenPatterns.insert(item.grammarId).inserted {
                streaks[item.grammarId] = 0
                ordered.append(item.grammarId)
                requiredStreaks[item.grammarId] = item.level == "Particles"
                    ? particleRequiredStreak
                    : defaultRequiredStreak
            }
        }
        orderedPatternIds = ordered
        totalPatterns = seenPatterns.count

        // Build the initial queue from the session items
        queue = items
        introQueue = buildIntroQueue(items: items, newPatternIds: newPatternIds)
        introTotal = introQueue.count
        shuffleChoicesForCurrent()
    }

    private func shuffleChoicesForCurrent() {
        guard let item = currentItem else { return }
        var choices = item.wrongChoices
        choices.append(item.blankTarget)
        shuffledChoices = choices.shuffled()
    }

    // MARK: - Answer Handling

    private func handleAnswer(_ choice: String, for item: SessionExercise) {
        selectedAnswer = choice
        showingResult = true
        questionsAnswered += 1

        let isCorrect = choice == item.blankTarget

        if isCorrect {
            let newStreak = (streaks[item.grammarId] ?? 0) + 1
            streaks[item.grammarId] = newStreak
            let hasFailed = failedPatterns.contains(item.grammarId)
            let isNewPattern = activeNewPatternIds.contains(item.grammarId)
            // Review patterns: first-try correct completes immediately; after a mistake
            // they need requiredStreak in a row. New patterns always need the full
            // requiredStreak of passes before they're dismissed this session.
            if isNewPattern || hasFailed {
                if newStreak >= requiredStreak(for: item.grammarId) {
                    completedPatterns.insert(item.grammarId)
                } else if isNewPattern {
                    ensureUpcomingExercise(for: item)
                }
            } else {
                completedPatterns.insert(item.grammarId)
            }
        } else {
            // Reset this pattern's streak
            streaks[item.grammarId] = 0
            completedPatterns.remove(item.grammarId)
            failedPatterns.insert(item.grammarId)

            // Build retry exercises so the streak can reach the required count from 0.
            // Use different sentences from the pool where possible.
            let required = requiredStreak(for: item.grammarId)
            var retryItems: [SessionExercise] = []
            let alternatives: [SessionExercise] = {
                guard let pool = exercisePool[item.grammarId] else { return [] }
                return pool.filter { $0.id != item.id }.shuffled()
            }()

            for i in 0..<required {
                if i < alternatives.count {
                    retryItems.append(alternatives[i])
                } else {
                    retryItems.append(item)
                }
            }

            // Spread retries into the rest of the queue with a minimum gap so the
            // pattern isn't re-tested immediately after the answer was just shown.
            // Near the end of a session the gap shrinks naturally as the queue empties.
            var lastPos = 0
            for retry in retryItems {
                let minIdx = min(lastPos + 3, queue.count)
                let maxIdx = queue.count
                let pos = minIdx < maxIdx ? Int.random(in: minIdx...maxIdx) : queue.count
                queue.insert(retry, at: pos)
                lastPos = pos
            }
        }

        triggerHaptic(correct: isCorrect)
        recordOutcome(correct: isCorrect, for: item)

        withAnimation(.easeInOut(duration: 0.2)) {
            showExplanation = true
        }
    }

    /// Guarantee an incomplete new pattern has at least one more question queued,
    /// so it can always reach its required streak even when the session builder
    /// queued fewer sentences than needed (e.g. a pattern with a tiny pool).
    private func ensureUpcomingExercise(for item: SessionExercise) {
        guard !queue.dropFirst().contains(where: { $0.grammarId == item.grammarId }) else { return }
        let alternatives = (exercisePool[item.grammarId] ?? []).filter { $0.id != item.id }
        let next = alternatives.randomElement() ?? item
        // Same minimum gap as the retry path so the pattern isn't re-tested
        // immediately after its answer was just shown.
        let pos = min(4, queue.count)
        queue.insert(next, at: pos)
    }

    // MARK: - Mark as Known

    /// Schedule `grammarId` far out and drop it from this session. A new pattern is
    /// swapped for the next unseen one so the session keeps its size.
    private func markKnown(_ grammarId: String) {
        SRSEngine.markKnown(grammarId: grammarId, context: modelContext)

        let wasNew = activeNewPatternIds.contains(grammarId)
        let introIndex = introQueue.firstIndex { $0.grammarId == grammarId }
        let isParticle = queue.first { $0.grammarId == grammarId }?.level == "Particles"

        // Drop every trace of the pattern; its outcomes are discarded so the
        // end-of-session flush doesn't overwrite the "known" schedule.
        queue.removeAll { $0.grammarId == grammarId }
        introQueue.removeAll { $0.grammarId == grammarId }
        orderedPatternIds.removeAll { $0 == grammarId }
        streaks[grammarId] = nil
        requiredStreaks[grammarId] = nil
        patternOutcomes[grammarId] = nil
        completedPatterns.remove(grammarId)
        failedPatterns.remove(grammarId)
        activeNewPatternIds.remove(grammarId)
        totalPatterns = orderedPatternIds.count
        if introIndex != nil { introTotal -= 1 }

        if wasNew, !isParticle, let replacementNewPattern {
            let replacement = replacementNewPattern(Set(orderedPatternIds).union([grammarId]))
            insertNewPattern(replacement, introAt: introIndex ?? 0, freshIntroRun: introIndex == nil)
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            selectedAnswer = nil
            explainedChoice = nil
            showingResult = false
            showExplanation = false
        }

        // Same skip-ahead as `advanceToNext`, in case the next question's pattern is done.
        while let next = queue.first, completedPatterns.contains(next.grammarId), !isSessionComplete {
            queue.removeFirst()
        }

        if queue.isEmpty || isSessionComplete {
            if patternOutcomes.isEmpty {
                flushPatternRatings()
                dismiss()
            } else {
                finishSession()
            }
            return
        }
        shuffleChoicesForCurrent()
    }

    /// Add a freshly chosen new pattern: its intro card at `introAt`, and its
    /// sentences spread through the rest of the queue. `freshIntroRun` restarts
    /// the "1 of N" count when the intro cards had already all been shown.
    private func insertNewPattern(_ items: [SessionExercise], introAt: Int, freshIntroRun: Bool) {
        guard let first = items.first else { return }
        let grammarId = first.grammarId
        activeNewPatternIds.insert(grammarId)
        orderedPatternIds.append(grammarId)
        streaks[grammarId] = 0
        requiredStreaks[grammarId] = defaultRequiredStreak
        totalPatterns = orderedPatternIds.count

        if freshIntroRun && introQueue.isEmpty { introTotal = 0 }
        introQueue.insert(first, at: min(introAt, introQueue.count))
        introTotal += 1

        // Same minimum gap as the retry path, so repeats aren't back-to-back.
        var lastPos = -3
        for item in items {
            let minIdx = min(lastPos + 3, queue.count)
            let pos = Int.random(in: minIdx...queue.count)
            queue.insert(item, at: pos)
            lastPos = pos
        }
    }

    // MARK: - Navigation

    private func advanceToNext() {
        speaker.stop()

        // Remove the item we just answered from the front of the queue
        if !queue.isEmpty {
            queue.removeFirst()
        }

        // Check if the session is done
        if isSessionComplete || queue.isEmpty {
            finishSession()
            return
        }

        // If the next pattern in queue is already completed, skip ahead
        // to keep things moving (only skip if there are incomplete patterns remaining)
        while let next = queue.first,
              completedPatterns.contains(next.grammarId),
              !isSessionComplete {
            queue.removeFirst()
            if queue.isEmpty { break }
        }

        if queue.isEmpty || isSessionComplete {
            finishSession()
            return
        }

        selectedAnswer = nil
        explainedChoice = nil
        showingResult = false
        showExplanation = false
        shuffleChoicesForCurrent()
    }

    /// Save ratings and swap the question UI for the in-place summary card.
    private func finishSession() {
        flushPatternRatings()
        recordLastStudyDate()
        // Ratings were just flushed, so the remaining work reflects this session.
        let remaining = remainingWork?() ?? (due: 0, new: 0)
        summaryDueCount = remaining.due
        summaryNewCount = remaining.new
        withAnimation(.easeInOut(duration: 0.25)) {
            showExplanation = false
            showSummary = true
        }
    }

    /// Start the follow-up session on this same screen.
    private func keepReviewing() {
        guard let next = buildNextSession?(), !next.items.isEmpty else {
            dismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            initializeSession(items: next.items, newPatternIds: next.newPatternIds)
            showSummary = false
        }
    }

    /// Share of distinct sentences answered correctly on the first try this session.
    private var firstTryAccuracy: Double? {
        let firstAttempts = patternOutcomes.values.flatMap(\.firstAttempts.values)
        guard !firstAttempts.isEmpty else { return nil }
        return Double(firstAttempts.filter { $0 }.count) / Double(firstAttempts.count)
    }

    // MARK: - Button Styling

    /// Visual state of an answer tile: neutral before answering; afterwards the
    /// correct answer turns green and a wrong selection turns rose.
    /// Why `choice` is wrong for this item, if it's a distractor with an explanation.
    private func wrongChoiceExplanation(for choice: String, in item: SessionExercise) -> String? {
        guard choice != item.blankTarget,
              let idx = item.wrongChoices.firstIndex(of: choice),
              idx < item.wrongChoiceExplanations.count else { return nil }
        let text = item.wrongChoiceExplanations[idx]
        return text.isEmpty ? nil : text
    }

    private func answerState(for choice: String) -> AnswerTileButtonStyle.State {
        guard let selected = selectedAnswer, let item = currentItem else {
            return .neutral
        }
        if choice == item.blankTarget { return .correct }
        if choice == selected { return .wrong }
        return .dimmed
    }

    // MARK: - Study date & SRS

    /// Stamp the "Last review" time shown on the home page.
    private func recordLastStudyDate() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastStudyDate")
    }

    /// Append one on-screen answer to the per-pattern accumulator. No FSRS scheduling
    /// happens here — that's deferred to `flushPatternRatings()` so the scheduler sees
    /// one rating per pattern per session (matching FSRS's assumed cadence).
    private func recordOutcome(correct: Bool, for item: SessionExercise) {
        var outcomes = patternOutcomes[item.grammarId] ?? PatternOutcomes()
        // Only the first attempt at each distinct sentence counts toward the aggregate
        // rating. Retries (same exerciseId or pool alternates after a wrong answer)
        // still bump the totals below but don't overwrite the first-try record.
        if outcomes.firstAttempts[item.id] == nil {
            outcomes.firstAttempts[item.id] = correct
        }
        outcomes.totalAnswers += 1
        if correct { outcomes.correctAnswers += 1 }
        patternOutcomes[item.grammarId] = outcomes

        StudyLog.record(correct: correct, context: modelContext)
    }

    /// Emit one FSRS rating per pattern based on accumulated first-attempt outcomes.
    /// Called on every session-exit path; the `didFlushRatings` guard makes repeat calls
    /// (e.g. advanceToNext → dismiss → onDisappear) no-ops.
    private func flushPatternRatings() {
        guard !didFlushRatings else { return }
        didFlushRatings = true

        for (grammarId, outcomes) in patternOutcomes {
            let firstTryCorrect = outcomes.firstAttempts.values.filter { $0 }.count
            let firstTryTotal = outcomes.firstAttempts.count
            guard let rating = SRSEngine.aggregateRating(correct: firstTryCorrect, total: firstTryTotal) else {
                continue
            }

            let descriptor = FetchDescriptor<SRSRecord>(
                predicate: #Predicate { $0.grammarId == grammarId }
            )
            do {
                // New patterns get their record only now, once they've actually been
                // answered — session builders no longer create records up front.
                let record = try modelContext.fetch(descriptor).first ?? {
                    let newRecord = SRSRecord(grammarId: grammarId)
                    modelContext.insert(newRecord)
                    // Count it against today's new-pattern allowance (grammar only;
                    // particles aren't paced by the daily plan).
                    if activeNewPatternIds.contains(grammarId) {
                        DailyPlanner.recordIntroduction()
                    }
                    return newRecord
                }()
                SRSEngine.applyRating(
                    record: record,
                    rating: rating,
                    attemptsDelta: outcomes.totalAnswers,
                    correctDelta: outcomes.correctAnswers
                )
            } catch {
                print("Error fetching SRS record for \(grammarId): \(error)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            print("Error saving SRS updates: \(error)")
        }
    }

    private func triggerHaptic(correct: Bool) {
        if correct {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Pattern Intro Card

/// One-time card for a brand-new pattern, shown in sequence before the quiz starts:
/// the pattern, its meaning, and example sentences with the pattern highlighted.
private struct PatternIntroCard: View {
    let item: SessionExercise
    let examples: [SessionExercise]
    /// 1-based index of this card among the session's new patterns.
    let position: Int
    let total: Int
    let onMarkKnown: () -> Void
    let onContinue: () -> Void
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    /// Example sentence with the blank filled in and the grammar target highlighted.
    private func highlightedSentence(for exercise: SessionExercise) -> AttributedString {
        let filled: String
        if exercise.exampleSentence.range(of: "_{2,}", options: .regularExpression) != nil {
            filled = exercise.exampleSentence.replacingOccurrences(
                of: "_{2,}",
                with: exercise.blankTarget,
                options: .regularExpression
            )
        } else {
            filled = exercise.exampleSentence
        }
        var attributed = AttributedString(filled)
        var highlight = attributed.range(of: exercise.blankTarget)
        if filled == exercise.exampleSentence, let r = exercise.blankRange {
            let lower = AttributedString.Index(r.lowerBound, within: attributed)
            let upper = AttributedString.Index(r.upperBound, within: attributed)
            if let lower, let upper { highlight = lower..<upper }
        }
        if let range = highlight {
            attributed[range].foregroundColor = Theme.brand
            attributed[range].font = .system(size: scaled(18), weight: .bold)
        }
        return attributed
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: scaled(11), weight: .semibold))
                    Text("NEW PATTERN · \(item.level)")
                        .font(.system(size: scaled(11), weight: .semibold))
                        .tracking(1.0)
                }
                .foregroundStyle(Theme.brand)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.brandTint))
                .overlay(Capsule().strokeBorder(Theme.brandBorder, lineWidth: 1))

                if total > 1 {
                    Text("\(position) of \(total)")
                        .font(.system(size: scaled(12), weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkMuted)
                }

                Text(item.pattern)
                    .font(.system(size: scaled(30), weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                Text(item.meaning)
                    .font(.system(size: scaled(17)))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 14) {
                Text("HOW IT'S USED")
                    .font(.system(size: scaled(11), weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Theme.inkMuted)

                ForEach(examples, id: \.id) { example in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlightedSentence(for: example))
                            .font(.system(size: scaled(18)))
                            .foregroundStyle(Theme.ink)

                        Text(example.translation)
                            .font(.system(size: scaled(14)))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .tactileCard(cornerRadius: 20)
            .padding(.horizontal)

            Button(action: onContinue) {
                Text(position < total ? "Got It — Next Pattern" : "Got It — Start Practicing")
                    .font(.system(size: scaled(17), weight: .bold))
            }
            .buttonStyle(TactilePrimaryButtonStyle())
            .padding(.horizontal)

            Button(action: onMarkKnown) {
                Text("I already know this")
                    .font(.system(size: scaled(14), weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Session Summary Card

/// End-of-session card shown in place of the last question, so finishing a session
/// doesn't bounce back to Home before offering to continue.
private struct SessionSummaryCard: View {
    let patternCount: Int
    let questionsAnswered: Int
    let firstTryAccuracy: Double?
    let remainingDue: Int
    let remainingNew: Int
    let canKeepReviewing: Bool
    let onKeepReviewing: () -> Void
    let onDone: () -> Void
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    /// "Still to do today: 3 reviews and 2 new patterns."
    private var remainingWorkText: String {
        var parts: [String] = []
        if remainingDue > 0 {
            parts.append(remainingDue == 1 ? "1 review" : "\(remainingDue) reviews")
        }
        if remainingNew > 0 {
            parts.append(remainingNew == 1 ? "1 new pattern" : "\(remainingNew) new patterns")
        }
        return "Still to do today: \(parts.formatted(.list(type: .and)))."
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: scaled(15)))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(value)
                .font(.system(size: scaled(15), weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.inkMuted)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: scaled(44)))
                    .foregroundStyle(Theme.correctBorder)
                Text("Session Complete")
                    .font(.system(size: scaled(26), weight: .bold))
                    .foregroundStyle(Theme.ink)
            }

            VStack(spacing: 10) {
                statRow("Patterns", value: "\(patternCount)")
                statRow("Questions", value: "\(questionsAnswered)")
                if let accuracy = firstTryAccuracy {
                    statRow("First-try accuracy", value: accuracy.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .padding(16)
            .tactileCard(cornerRadius: 20)
            .padding(.horizontal)

            VStack(spacing: 12) {
                if canKeepReviewing && (remainingDue > 0 || remainingNew > 0) {
                    Text(remainingWorkText)
                        .font(.system(size: scaled(14)))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)

                    Button(action: onKeepReviewing) {
                        Text("Keep Going")
                            .font(.system(size: scaled(17), weight: .bold))
                    }
                    .buttonStyle(TactilePrimaryButtonStyle())

                    Button(action: onDone) {
                        Text("Done")
                            .font(.system(size: scaled(17), weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(TactileCardButtonStyle(cornerRadius: 16))
                } else {
                    if canKeepReviewing {
                        Text("That's today's plan done.")
                            .font(.system(size: scaled(14)))
                            .foregroundStyle(Theme.inkMuted)
                    }

                    Button(action: onDone) {
                        Text("Done")
                            .font(.system(size: scaled(17), weight: .bold))
                    }
                    .buttonStyle(TactilePrimaryButtonStyle())
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Session Progress Bar

private struct SessionProgressBar: View {
    let orderedPatternIds: [String]
    let streaks: [String: Int]
    let completedPatterns: Set<String>
    let failedPatterns: Set<String>
    let requiredStreaks: [String: Int]
    let defaultRequiredStreak: Int

    var body: some View {
        GeometryReader { geometry in
            let count = orderedPatternIds.count
            guard count > 0 else { return AnyView(EmptyView()) }
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(count - 1)
            let segmentWidth = (geometry.size.width - totalSpacing) / CGFloat(count)

            return AnyView(
                HStack(spacing: spacing) {
                    ForEach(Array(orderedPatternIds.enumerated()), id: \.element) { _, patternId in
                        let streak = streaks[patternId] ?? 0
                        let isCompleted = completedPatterns.contains(patternId)
                        let hasFailed = failedPatterns.contains(patternId)
                        let required = requiredStreaks[patternId] ?? defaultRequiredStreak

                        // After a wrong answer with streak 0, show a small red bar.
                        // Otherwise fill proportionally to streak progress.
                        let fraction: CGFloat = {
                            if isCompleted { return 1.0 }
                            if hasFailed && streak == 0 { return 0.15 }
                            return CGFloat(streak) / CGFloat(required)
                        }()

                        segmentView(
                            streak: streak,
                            fraction: fraction,
                            isCompleted: isCompleted,
                            hasFailed: hasFailed,
                            width: segmentWidth,
                            height: geometry.size.height
                        )
                    }
                }
            )
        }
    }

    private func segmentView(streak: Int, fraction: CGFloat, isCompleted: Bool, hasFailed: Bool, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Background track
            RoundedRectangle(cornerRadius: height / 2)
                .fill(Theme.hairline)
                .frame(width: width, height: height)

            // Filled portion
            if fraction > 0 {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(segmentColor(streak: streak, isCompleted: isCompleted, hasFailed: hasFailed))
                    .frame(width: max(height, width * fraction), height: height)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fraction)
        .animation(.easeInOut(duration: 0.3), value: isCompleted)
    }

    /// Patterns with no mistakes: always green.
    /// Patterns after a mistake: red (0) → orange (1) → yellow (2) → green (3/completed).
    private func segmentColor(streak: Int, isCompleted: Bool, hasFailed: Bool) -> Color {
        if isCompleted { return Theme.correctBorder }
        if !hasFailed { return Theme.correctBorder }
        switch streak {
        case 0: return Theme.incorrectBorder
        case 1: return Theme.amber
        case 2: return Color(light: 0xFBBF24, dark: 0xFCD34D)
        default: return Theme.correctBorder
        }
    }
}

// MARK: - Vocab Chips

/// One tappable vocab chip; tap shows a popover with reading + meaning.
private struct VocabChip: View {
    let item: VocabItem
    let fontSize: CGFloat
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            Text(item.word)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        }
        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
            VStack(spacing: 4) {
                Text(item.reading)
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(Theme.inkMuted)
                Text(item.word)
                    .font(.system(size: fontSize + 5, weight: .semibold))
                Text(item.meaning)
                    .font(.system(size: fontSize))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Minimal left-aligned flow layout: wraps chips onto new rows as needed.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Selectable Text (character-level selection)

private struct SelectableText: UIViewRepresentable {
    let text: String
    var fontSize: CGFloat = 17
    var fontWeight: UIFont.Weight = .regular
    var textColor: UIColor = .label
    var textAlignment: NSTextAlignment = .center
    /// When both are set and `rubyBase` occurs in `text`, `rubyReading` is drawn as
    /// furigana above the first occurrence (used for the revealed grammar target).
    var rubyBase: String? = nil
    var rubyReading: String? = nil
    /// When set, a tappable speaker icon is appended inline after the text.
    var onSpeak: (() -> Void)? = nil

    /// Link target for the inline speaker attachment; intercepted by the coordinator.
    private static let speakURL = URL(string: "jlptdrill-speak://sentence")!

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSpeak: (() -> Void)?

        // Tapping the speaker link triggers speech instead of opening a URL.
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, url == SelectableText.speakURL else { return defaultAction }
            return UIAction { [weak self] _ in self?.onSpeak?() }
        }

        // No long-press link preview/menu for the speaker icon.
        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            guard case .link(let url) = textItem.content, url == SelectableText.speakURL else {
                return UITextItem.MenuConfiguration(menu: defaultMenu)
            }
            return nil
        }
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        // Ruby annotations (kCTRubyAnnotationAttributeName) render under the default
        // TextKit 2 stack on current OSes; forcing TextKit 1 compatibility mode
        // (`_ = textView.layoutManager`) suppresses them, so don't.
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSpeak = onSpeak
        if onSpeak != nil {
            let attributed = NSMutableAttributedString(
                attributedString: rubyAttributedString() ?? plainAttributedString()
            )
            attributed.append(speakerAttachment())
            textView.attributedText = attributed
        } else if let attributed = rubyAttributedString() {
            textView.attributedText = attributed
        } else {
            textView.font = .systemFont(ofSize: fontSize, weight: fontWeight)
            textView.textColor = textColor
            textView.textAlignment = textAlignment
            textView.text = text
        }
        textView.invalidateIntrinsicContentSize()
    }

    /// Plain styled text, used when the speaker icon needs an attributed string but ruby doesn't apply.
    private func plainAttributedString() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: fontWeight),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ])
    }

    /// A space plus an inline speaker symbol, linked to `speakURL` so taps reach the coordinator.
    private func speakerAttachment() -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        let config = UIImage.SymbolConfiguration(pointSize: fontSize * 0.85, weight: .regular)
        // Original rendering mode keeps the icon grey rather than tinted as a link.
        guard let image = UIImage(systemName: "speaker.wave.2", withConfiguration: config)?
            .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal) else {
            return NSAttributedString()
        }
        image.accessibilityLabel = "Read sentence aloud"

        let attachment = NSTextAttachment(image: image)
        // Centre the icon slightly below the kanji midline so it sits with the kana and 。
        // rather than floating at the top of the line.
        attachment.bounds = CGRect(
            x: 0,
            y: fontSize * 0.27 - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )

        let result = NSMutableAttributedString(string: " ", attributes: [.font: font])
        result.append(NSAttributedString(attachment: attachment))
        result.addAttribute(.link, value: Self.speakURL, range: NSRange(location: 1, length: 1))
        return result
    }

    /// Attributed string with a furigana annotation over the first occurrence of
    /// `rubyBase`, or nil when ruby isn't applicable (plain-text path is used instead).
    private func rubyAttributedString() -> NSAttributedString? {
        guard let base = rubyBase, let reading = rubyReading,
              !base.isEmpty, !reading.isEmpty else { return nil }
        // Annotate only the kanji core, not surrounding kana shared with the reading
        // (に決まっている/にきまっている → 決/き). Annotating the kana too makes
        // TextKit reserve the ruby's full width inline, punching a gap into the base line.
        let baseChars = Array(base), readingChars = Array(reading)
        var prefix = 0
        while prefix < baseChars.count && prefix < readingChars.count
                && baseChars[prefix] == readingChars[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < baseChars.count - prefix && suffix < readingChars.count - prefix
                && baseChars[baseChars.count - 1 - suffix] == readingChars[readingChars.count - 1 - suffix] { suffix += 1 }
        let coreBase = String(baseChars[prefix..<(baseChars.count - suffix)])
        let coreReading = String(readingChars[prefix..<(readingChars.count - suffix)])
        guard !coreBase.isEmpty, !coreReading.isEmpty else { return nil }

        let nsText = text as NSString
        let baseRange = nsText.range(of: base)
        guard baseRange.location != NSNotFound else { return nil }
        let range = NSRange(
            location: baseRange.location + String(baseChars[0..<prefix]).utf16.count,
            length: (coreBase as NSString).length
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        // Extra leading so the ruby glyphs above the first line aren't clipped.
        paragraphStyle.lineHeightMultiple = 1.35

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: fontWeight),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ])

        let annotation = CTRubyAnnotationCreateWithAttributes(
            .auto, .auto, .before,
            coreReading as CFString,
            [kCTRubyAnnotationSizeFactorAttributeName: 0.5] as CFDictionary
        )
        attributed.addAttribute(
            NSAttributedString.Key(kCTRubyAnnotationAttributeName as String),
            value: annotation,
            range: range
        )
        return attributed
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
    }
}

#Preview {
    NavigationStack {
        ExerciseView(
            sessionItems: [
                SessionExercise(
                    id: "n4_001_1",
                    grammarId: "n4_001",
                    pattern: "〜そうだ",
                    meaning: "looks like; appears that",
                    level: "N4",
                    exampleSentence: "雨が降りそうだ。",
                    translation: "It looks like it's going to rain.",
                    blankTarget: "そうだ",
                    wrongChoices: ["ようだ", "らしい", "みたいだ"],
                    wrongChoiceExplanations: []
                )
            ],
            exercisePool: [:]
        )
    }
    .modelContainer(for: [SRSRecord.self, StudyLog.self], inMemory: true)
}
