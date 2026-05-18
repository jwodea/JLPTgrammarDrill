import SwiftUI
import SwiftData

struct ExerciseView: View {
    let sessionItems: [SessionExercise]
    let exercisePool: [String: [SessionExercise]]
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
        return item.exampleSentence.replacingOccurrences(of: item.blankTarget, with: blank)
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

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

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

                            Spacer(minLength: 30)

                            // Question
                            VStack(spacing: 12) {
                                if item.level == "Particles" {
                                    HStack(spacing: 4) {
                                        Image(systemName: "character.ja")
                                            .font(.system(size: scaled(10), weight: .semibold))
                                        Text("particle")
                                            .font(.system(size: scaled(11), weight: .semibold))
                                            .tracking(0.5)
                                    }
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
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
                                            .background(buttonBackground(for: choice))
                                            .foregroundColor(buttonForeground(for: choice))
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(buttonBorder(for: choice), lineWidth: 1.5)
                                            )
                                    }
                                    .disabled(selectedAnswer != nil)
                                    .animation(.easeInOut(duration: 0.2), value: selectedAnswer)
                                }
                            }
                            .padding(.horizontal)

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
                                        textAlignment: .left
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
                                            .padding(.vertical, 12)
                                            .background(Color.accentColor)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                    }
                                    .padding(.top, 4)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(16)
                                .padding(.horizontal)
                                .transition(.move(edge: .bottom))
                                .id("explanation")
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
            // First-try correct: immediately complete. After a mistake: need requiredStreak in a row.
            if !hasFailed || newStreak >= requiredStreak(for: item.grammarId) {
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

            // First retry goes right after the current item (position 1) for immediate re-test.
            queue.insert(retryItems[0], at: min(1, queue.count))

            // Remaining retries (2nd and 3rd) get mixed randomly into the rest of the queue.
            // We pick random positions from index 2 onward (past current + first retry),
            // ensuring at least one other item separates them where possible.
            for i in 1..<retryItems.count {
                let minIdx = min(2 + i, queue.count) // spread them out a bit
                let maxIdx = queue.count
                if minIdx < maxIdx {
                    let pos = Int.random(in: minIdx...maxIdx)
                    queue.insert(retryItems[i], at: pos)
                } else {
                    queue.append(retryItems[i])
                }
            }
        }

        triggerHaptic(correct: isCorrect)
        updateSRS(correct: isCorrect, for: item)

        withAnimation(.easeInOut(duration: 0.2)) {
            showExplanation = true
        }
    }

    // MARK: - Navigation

    private func advanceToNext() {
        // Remove the item we just answered from the front of the queue
        if !queue.isEmpty {
            queue.removeFirst()
        }

        // Check if the session is done
        if isSessionComplete || queue.isEmpty {
            updateStreak()
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
            updateStreak()
            dismiss()
            return
        }

        selectedAnswer = nil
        showingResult = false
        showExplanation = false
        shuffleChoicesForCurrent()
    }

    // MARK: - Button Styling

    private func buttonBackground(for choice: String) -> Color {
        guard let selected = selectedAnswer, let item = currentItem else {
            return Color(.secondarySystemBackground)
        }
        if choice == item.blankTarget {
            return Color.green.opacity(0.2)
        }
        if choice == selected && selected != item.blankTarget {
            return Color.red.opacity(0.2)
        }
        return Color(.secondarySystemBackground)
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

    private func buttonBorder(for choice: String) -> Color {
        guard let selected = selectedAnswer, let item = currentItem else {
            return Color.secondary.opacity(0.3)
        }
        if choice == item.blankTarget {
            return Color.green
        }
        if choice == selected && selected != item.blankTarget {
            return Color.red
        }
        return Color.secondary.opacity(0.3)
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

    private func updateSRS(correct: Bool, for item: SessionExercise) {
        let grammarId = item.grammarId
        let descriptor = FetchDescriptor<SRSRecord>(
            predicate: #Predicate { $0.grammarId == grammarId }
        )
        do {
            if let record = try modelContext.fetch(descriptor).first {
                SRSEngine.processAnswer(record: record, correct: correct)
                try modelContext.save()
            }
        } catch {
            print("Error updating SRS: \(error)")
        }
        StudyLog.record(correct: correct, context: modelContext)
    }

    private func triggerHaptic(correct: Bool) {
        if correct {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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

// MARK: - Selectable Text (character-level selection)

private struct SelectableText: UIViewRepresentable {
    let text: String
    var fontSize: CGFloat = 17
    var fontWeight: UIFont.Weight = .regular
    var textColor: UIColor = .label
    var textAlignment: NSTextAlignment = .center

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
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
        textView.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        textView.textColor = textColor
        textView.textAlignment = textAlignment
        textView.text = text
        textView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
    }
}
