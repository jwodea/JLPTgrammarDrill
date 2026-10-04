import SwiftUI
import SwiftData
import SwiftFSRS
import CoreText

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
    /// Grammar IDs being introduced for the first time this session. Each shows
    /// a one-time intro card (pattern, meaning, examples) before its first question.
    var newPatternIds: Set<String> = []
    /// Fired only when the session finishes naturally (all patterns mastered or queue
    /// exhausted) — not when the user bails out via the X button or a swipe-back.
    /// Lets the presenter offer a "keep reviewing" prompt when more cards are due.
    var onSessionComplete: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
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
    // Per-pattern required streak. Particles only need 1 correct retry; grammar needs 3.
    @State private var requiredStreaks: [String: Int] = [:]
    // Per-pattern aggregated outcomes — drives a single FSRS rating per pattern at end of session.
    @State private var patternOutcomes: [String: PatternOutcomes] = [:]
    // Guards against flushing twice when both `advanceToNext` and `onDisappear` fire.
    @State private var didFlushRatings = false
    // New patterns whose intro card has been dismissed this session.
    @State private var introducedPatterns: Set<String> = []

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

    // MARK: - Chips

    private func chip(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: scaled(10), weight: .semibold))
            Text(label)
                .font(.system(size: scaled(11), weight: .semibold))
                .tracking(0.5)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    /// Register chip — shown only for marked registers; neutral/nil renders nothing.
    @ViewBuilder
    private func registerChip(for register: Register) -> some View {
        switch register {
        case .casual:
            chip(label: "casual speech", icon: "bubble.left.and.bubble.right", color: .teal)
        case .formal:
            chip(label: "formal", icon: "building.columns", color: .indigo)
        case .written:
            chip(label: "written language", icon: "book", color: .purple)
        case .neutral:
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            GlassBackdrop().ignoresSafeArea()

            if let item = currentItem {
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

                                Text("\(completedPatterns.count)/\(totalPatterns) mastered")
                                    .font(.system(size: scaled(12)))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top)

                            if isIntroducingNewPattern(item) {
                                PatternIntroCard(item: item, examples: introExamples(for: item)) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        _ = introducedPatterns.insert(item.grammarId)
                                    }
                                }
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    flushPatternRatings()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            initializeSession()
        }
        .onDisappear {
            // Safety net for any dismissal path (system gesture, etc.) that
            // skips both the X button and `advanceToNext`. The flush is idempotent.
            flushPatternRatings()
        }
    }

    // MARK: - Question Content

    /// The quiz UI for the current item: sentence, answer grid, vocab chips, explanation card.
    @ViewBuilder
    private func questionContent(for item: SessionExercise) -> some View {
        Spacer(minLength: 30)

        // Question
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                if item.level == "Particles" {
                    chip(label: "particle", icon: "character.ja", color: .orange)
                }
                if let register = item.register, register != .neutral {
                    registerChip(for: register)
                }
            }

            SelectableText(
                text: blankedSentence,
                fontSize: scaled(26),
                fontWeight: .bold,
                textColor: .label,
                textAlignment: .center
            )
            .padding(.horizontal)

            SelectableText(
                text: item.translation,
                fontSize: scaled(17),
                fontWeight: .regular,
                textColor: .secondaryLabel,
                textAlignment: .center
            )
            .padding(.horizontal)
        }

        Spacer(minLength: 30)

        // Answer buttons (2x2 grid)
        GlassEffectContainer(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(shuffledChoices, id: \.self) { choice in
                    Button {
                        guard selectedAnswer == nil else { return }
                        handleAnswer(choice, for: item)
                    } label: {
                        Text(choice)
                            .font(.system(size: scaled(17)))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(buttonForeground(for: choice))
                            .contentShape(Rectangle())
                            .glassEffect(buttonGlass(for: choice), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAnswer != nil)
                    .animation(.easeInOut(duration: 0.2), value: selectedAnswer)
                }
            }
        }
        .padding(.horizontal)

        // Significant-vocab chips — tap for reading + meaning
        if !item.vocab.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("VOCAB")
                    .font(.system(size: scaled(10), weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(Color.secondary.opacity(0.7))
                ChipFlowLayout(spacing: 8) {
                    ForEach(item.vocab, id: \.self) { vocabItem in
                        VocabChip(item: vocabItem, fontSize: scaled(15))
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
                    Text(item.wrongChoiceExplanations[idx])
                        .font(.system(size: scaled(15)))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.bottom, 4)
                }

                Text(item.pattern)
                    .font(.system(size: scaled(19), weight: .bold))

                Text(item.meaning)
                    .font(.system(size: scaled(16)))
                    .foregroundColor(.secondary)

                SelectableText(
                    text: filledSentence,
                    fontSize: scaled(17),
                    fontWeight: .regular,
                    textColor: .label,
                    textAlignment: .left,
                    rubyBase: targetRuby?.base,
                    rubyReading: targetRuby?.reading
                )

                SelectableText(
                    text: item.translation,
                    fontSize: scaled(15),
                    fontWeight: .regular,
                    textColor: .secondaryLabel,
                    textAlignment: .left
                )

                Button {
                    advanceToNext()
                } label: {
                    Text(isSessionComplete ? "All Done" : "Next")
                        .font(.system(size: scaled(17), weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 4)
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal)
            .transition(.move(edge: .bottom))
            .id("explanation")
        }
    }

    // MARK: - New Pattern Introduction

    /// True while the current item's pattern is new this session and its intro
    /// card hasn't been dismissed yet.
    private func isIntroducingNewPattern(_ item: SessionExercise) -> Bool {
        newPatternIds.contains(item.grammarId) && !introducedPatterns.contains(item.grammarId)
    }

    /// Example sentences for the intro card, drawn from the pattern's full pool
    /// so the learner sees the pattern in context before being quizzed on it.
    private func introExamples(for item: SessionExercise) -> [SessionExercise] {
        let pool = exercisePool[item.grammarId] ?? []
        return pool.isEmpty ? [item] : Array(pool.prefix(2))
    }

    // MARK: - Session Initialization

    private func initializeSession() {
        // Collect unique grammar pattern IDs in order
        var seenPatterns = Set<String>()
        var ordered: [String] = []
        for item in sessionItems {
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

        // Build the initial queue from sessionItems
        queue = sessionItems
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
            let isNewPattern = newPatternIds.contains(item.grammarId)
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

    // MARK: - Navigation

    private func advanceToNext() {
        // Remove the item we just answered from the front of the queue
        if !queue.isEmpty {
            queue.removeFirst()
        }

        // Check if the session is done
        if isSessionComplete || queue.isEmpty {
            flushPatternRatings()
            updateStreak()
            onSessionComplete?()
            dismiss()
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
            flushPatternRatings()
            updateStreak()
            onSessionComplete?()
            dismiss()
            return
        }

        selectedAnswer = nil
        showingResult = false
        showExplanation = false
        shuffleChoicesForCurrent()
    }

    // MARK: - Button Styling

    /// Glass variant per answer state: neutral interactive glass before answering,
    /// green-tinted for the correct answer and red-tinted for a wrong selection after.
    private func buttonGlass(for choice: String) -> Glass {
        guard let selected = selectedAnswer, let item = currentItem else {
            return .regular.interactive()
        }
        if choice == item.blankTarget {
            return .regular.tint(.green.opacity(0.45))
        }
        if choice == selected && selected != item.blankTarget {
            return .regular.tint(.red.opacity(0.45))
        }
        return .regular
    }

    private func buttonForeground(for choice: String) -> Color {
        guard let selected = selectedAnswer, let item = currentItem else {
            return Color.primary
        }
        if choice == item.blankTarget {
            return Color.green
        }
        if choice == selected && selected != item.blankTarget {
            return Color.red
        }
        return Color.primary
    }

    // MARK: - Streak & SRS

    private func updateStreak() {
        let defaults = UserDefaults.standard
        let lastStudyInterval = defaults.double(forKey: "lastStudyDate")
        let streakCount = defaults.integer(forKey: "streakCount")

        if lastStudyInterval > 0 {
            let lastStudyDate = Date(timeIntervalSince1970: lastStudyInterval)
            if Calendar.current.isDateInToday(lastStudyDate) {
                // Already studied today
            } else if Calendar.current.isDateInYesterday(lastStudyDate) {
                defaults.set(streakCount + 1, forKey: "streakCount")
            } else {
                defaults.set(1, forKey: "streakCount")
            }
        } else {
            defaults.set(1, forKey: "streakCount")
        }

        defaults.set(Date.now.timeIntervalSince1970, forKey: "lastStudyDate")
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
                if let record = try modelContext.fetch(descriptor).first {
                    SRSEngine.applyRating(
                        record: record,
                        rating: rating,
                        attemptsDelta: outcomes.totalAnswers,
                        correctDelta: outcomes.correctAnswers
                    )
                }
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

/// One-time card shown before a brand-new pattern's first question:
/// the pattern, its meaning, and example sentences with the pattern highlighted.
private struct PatternIntroCard: View {
    let item: SessionExercise
    let examples: [SessionExercise]
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
            attributed[range].foregroundColor = .accentColor
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
                .foregroundColor(.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())

                Text(item.pattern)
                    .font(.system(size: scaled(30), weight: .bold))
                    .multilineTextAlignment(.center)

                Text(item.meaning)
                    .font(.system(size: scaled(17)))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 14) {
                Text("HOW IT'S USED")
                    .font(.system(size: scaled(10), weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(Color.secondary.opacity(0.7))

                ForEach(examples, id: \.id) { example in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlightedSentence(for: example))
                            .font(.system(size: scaled(18)))

                        Text(example.translation)
                            .font(.system(size: scaled(14)))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal)

            Button(action: onContinue) {
                Text("Got It — Start Practicing")
                    .font(.system(size: scaled(17), weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
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
                .fill(Color(.systemGray5))
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
        if isCompleted { return .green }
        if !hasFailed { return .green }
        switch streak {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        default: return .green
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
                .font(.system(size: fontSize))
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
            VStack(spacing: 4) {
                Text(item.reading)
                    .font(.system(size: fontSize - 2))
                    .foregroundColor(.secondary)
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

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
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
        if let attributed = rubyAttributedString() {
            textView.attributedText = attributed
        } else {
            textView.font = .systemFont(ofSize: fontSize, weight: fontWeight)
            textView.textColor = textColor
            textView.textAlignment = textAlignment
            textView.text = text
        }
        textView.invalidateIntrinsicContentSize()
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
