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
            GlassBackdrop().ignoresSafeArea()

            if isLoading {
                ProgressView("Loading particles…")
            } else if let item = currentExercise {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header — visually matches the Grammar Drill / Audio Drill home headers.
                            VStack(spacing: 6) {
                                Text("Particle Practice")
                                    .font(.system(size: scaled(36), weight: .heavy, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.orange, .orange.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                Text("Choose the right particle")
                                    .font(.system(size: scaled(13)))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 12)

                            Spacer(minLength: 20)

                            // Question
                            VStack(spacing: 12) {
                                Text(blankedSentence)
                                    .font(.system(size: scaled(26), weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)

                                if !item.translation.isEmpty {
                                    Text(item.translation)
                                        .font(.system(size: scaled(17)))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }

                            Spacer(minLength: 30)

                            // Answer buttons (2x2 grid)
                            GlassEffectContainer(spacing: 12) {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(shuffledChoices, id: \.self) { choice in
                                        Button {
                                            guard selectedAnswer == nil else { return }
                                            handleAnswer(choice)
                                        } label: {
                                            Text(choice)
                                                .font(.system(size: scaled(22), weight: .medium))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 18)
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

                            // Explanation card
                            if showExplanation {
                                VStack(alignment: .leading, spacing: 10) {
                                    // Show why the selected wrong answer is wrong
                                    if let selected = selectedAnswer,
                                       selected != item.blankTarget,
                                       let explanation = item.wrongChoiceExplanations[selected] {
                                        Text(explanation)
                                            .font(.system(size: scaled(15)))
                                            .foregroundColor(.red.opacity(0.8))
                                            .padding(.bottom, 4)
                                    }

                                    Text(item.particle)
                                        .font(.system(size: scaled(19), weight: .bold))

                                    Text(item.explanation)
                                        .font(.system(size: scaled(16)))
                                        .foregroundColor(.secondary)

                                    Text(filledSentence)
                                        .font(.system(size: scaled(17)))

                                    if !item.translation.isEmpty {
                                        Text(item.translation)
                                            .font(.system(size: scaled(15)))
                                            .foregroundColor(.secondary)
                                    }

                                    Button {
                                        advanceToNext()
                                    } label: {
                                        Text("Next")
                                            .font(.system(size: scaled(17), weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
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
        .onAppear {
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

    /// Glass variant per answer state: neutral interactive glass before answering,
    /// green-tinted for the correct answer and red-tinted for a wrong selection after.
    private func buttonGlass(for choice: String) -> Glass {
        guard let selected = selectedAnswer, let item = currentExercise else {
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
        guard let selected = selectedAnswer, let item = currentExercise else {
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

    // MARK: - Haptics

    private func triggerHaptic(correct: Bool) {
        if correct {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
