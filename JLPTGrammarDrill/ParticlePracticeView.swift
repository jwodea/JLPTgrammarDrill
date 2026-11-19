import SwiftUI
import SwiftData

/// Particle Practice — endless random exercises, no session tracking.
/// Weighted toward exercises the user has gotten wrong more often.
struct ParticlePracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    @State private var allExercises: [ParticleExercise] = []
    @State private var currentExercise: ParticleExercise?
    @State private var shuffledChoices: [String] = []
    @State private var selectedAnswer: String?
    @State private var showExplanation = false
    @State private var isLoading = true

    // Track accuracy within this session for weighting
    @State private var sessionWrong: Set<String> = []

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    private var blankedSentence: String {
        guard let item = currentExercise else { return "" }
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
        guard let item = currentExercise else { return "" }
        if item.exampleSentence.range(of: "_{2,}", options: .regularExpression) != nil {
            return item.exampleSentence.replacingOccurrences(
                of: "_{2,}",
                with: item.blankTarget,
                options: .regularExpression
            )
        }
        return item.exampleSentence
    }

    var body: some View {
        ZStack {
            TactileBackdrop().ignoresSafeArea()

            if isLoading {
                ProgressView("Loading particles…")
            } else if let item = currentExercise {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header — visually matches the Grammar Drill / Audio Drill home headers.
                            VStack(spacing: 6) {
                                Text("Particle Practice")
                                    .font(.system(size: scaled(34), weight: .heavy))
                                    .tracking(-0.8)
                                    .foregroundStyle(Theme.ink)
                                Text("Choose the right particle")
                                    .font(.system(size: scaled(13), weight: .medium))
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            .padding(.top, 12)

                            // Question card
                            VStack(alignment: .leading, spacing: 12) {
                                Text(blankedSentence)
                                    .font(.system(size: scaled(24), weight: .bold))
                                    .foregroundStyle(Theme.ink)

                                if !item.translation.isEmpty {
                                    Text(item.translation)
                                        .font(.system(size: scaled(16)))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .tactileCard()
                            .padding(.horizontal)

                            // Answer buttons (2x2 grid)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 12) {
                                ForEach(shuffledChoices, id: \.self) { choice in
                                    Button {
                                        guard selectedAnswer == nil else { return }
                                        handleAnswer(choice)
                                    } label: {
                                        Text(choice)
                                            .font(.system(size: scaled(22), weight: .semibold))
                                            .strikethrough(answerState(for: choice) == .wrong, color: Theme.incorrect)
                                    }
                                    .buttonStyle(AnswerTileButtonStyle(state: answerState(for: choice)))
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
                                       let explanation = item.wrongChoiceExplanations[selected] {
                                        Text(explanation)
                                            .font(.system(size: scaled(15)))
                                            .foregroundStyle(Theme.ink)
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(Theme.incorrectTint)
                                            )
                                            .padding(.bottom, 4)
                                    }

                                    Text(item.particle)
                                        .font(.system(size: scaled(19), weight: .bold))
                                        .foregroundStyle(Theme.ink)

                                    Text(item.explanation)
                                        .font(.system(size: scaled(16)))
                                        .foregroundStyle(Theme.inkMuted)

                                    Text(filledSentence)
                                        .font(.system(size: scaled(17)))
                                        .foregroundStyle(Theme.ink)

                                    if !item.translation.isEmpty {
                                        Text(item.translation)
                                            .font(.system(size: scaled(15)))
                                            .foregroundStyle(Theme.inkMuted)
                                    }

                                    Button {
                                        advanceToNext()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text("Next")
                                            Image(systemName: "arrow.right")
                                        }
                                        .font(.system(size: scaled(17), weight: .bold))
                                    }
                                    .buttonStyle(TactilePrimaryButtonStyle())
                                    .padding(.top, 4)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .tactileCard(cornerRadius: 20)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StatsView(kind: .particles)
                } label: {
                    Image(systemName: "chart.bar.fill")
                }
                .accessibilityLabel("Particle Stats")
            }
        }
        .onAppear {
            // Don't reshuffle the current question when returning from Stats.
            guard allExercises.isEmpty else { return }
            loadAndStart()
        }
    }

    // MARK: - Setup

    private func loadAndStart() {
        allExercises = ParticleLoader.loadAll()
        pickNext()
        isLoading = false
    }

    private func pickNext() {
        guard !allExercises.isEmpty else { return }

        // Fetch SRS records for weighting
        let descriptor = FetchDescriptor<SRSRecord>()
        let records = (try? modelContext.fetch(descriptor)) ?? []
        var recordMap: [String: SRSRecord] = [:]
        for record in records {
            recordMap[record.grammarId] = record
        }

        // Weight: wrong in this session = 3x, low SRS accuracy = higher, unseen = 1x
        struct W {
            let exercise: ParticleExercise
            let weight: Double
        }

        let weighted: [W] = allExercises.map { exercise in
            var w = 1.0
            if sessionWrong.contains(exercise.id) {
                w = 3.0
            } else if let record = recordMap[exercise.id] {
                w = 0.5 + 2.5 * (1.0 - record.accuracy)
            }
            return W(exercise: exercise, weight: w)
        }

        // Avoid repeating the same exercise back-to-back
        let candidates = currentExercise == nil
            ? weighted
            : weighted.filter { $0.exercise.id != currentExercise!.id }

        let totalWeight = candidates.reduce(0.0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<totalWeight)
        var picked = candidates[0].exercise
        for item in candidates {
            roll -= item.weight
            if roll <= 0 {
                picked = item.exercise
                break
            }
        }

        currentExercise = picked
        var choices = picked.wrongChoices
        choices.append(picked.blankTarget)
        shuffledChoices = choices.shuffled()
    }

    // MARK: - Answer Handling

    private func handleAnswer(_ choice: String) {
        guard let item = currentExercise else { return }
        selectedAnswer = choice

        let isCorrect = choice == item.blankTarget

        if !isCorrect {
            sessionWrong.insert(item.id)
        }

        triggerHaptic(correct: isCorrect)
        updateSRS(correct: isCorrect, for: item)

        withAnimation(.easeInOut(duration: 0.2)) {
            showExplanation = true
        }
    }

    private func advanceToNext() {
        selectedAnswer = nil
        showExplanation = false
        pickNext()
    }

    // MARK: - SRS

    private func updateSRS(correct: Bool, for item: ParticleExercise) {
        let exerciseId = item.id
        let descriptor = FetchDescriptor<SRSRecord>(
            predicate: #Predicate { $0.grammarId == exerciseId }
        )
        do {
            if let record = try modelContext.fetch(descriptor).first {
                SRSEngine.processAnswer(record: record, correct: correct)
            } else {
                let newRecord = SRSRecord(grammarId: exerciseId)
                modelContext.insert(newRecord)
                SRSEngine.processAnswer(record: newRecord, correct: correct)
            }
            try modelContext.save()
        } catch {
            print("Error updating SRS: \(error)")
        }
        StudyLog.record(correct: correct, context: modelContext)
    }

    // MARK: - Button Styling

    /// Visual state of an answer tile: neutral before answering; afterwards the
    /// correct answer turns green and a wrong selection turns rose.
    private func answerState(for choice: String) -> AnswerTileButtonStyle.State {
        guard let selected = selectedAnswer, let item = currentExercise else {
            return .neutral
        }
        if choice == item.blankTarget { return .correct }
        if choice == selected { return .wrong }
        return .dimmed
    }

    // MARK: - Haptics

    private func triggerHaptic(correct: Bool) {
        if correct {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
