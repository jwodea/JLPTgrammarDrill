import SwiftUI
import SwiftData
import SwiftFSRS

/// The active drill screen: prompt → record → result → grade → next.
struct AudioDrillView: View {
    let queue: [AudioQueueItem]
    let allExercises: [AudioExercise]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AudioDrillSettings.thresholdKey)
    private var threshold = AudioDrillSettings.defaultThreshold
    private let stripFinalCopula = true

    @AppStorage(FontSizeManager.scaleKey)
    private var fontScale = FontSizeManager.defaultScale

    @State private var index = 0
    @State private var phase: Phase = .prompt
    @State private var permissionGranted: Bool? = nil
    @State private var errorMessage: String?
    @State private var lastResult: MatchResult?
    @State private var lastAttempt: AudioAttempt?
    @State private var lastDurationMs: Int = 0
    @State private var lastRawTranscription: String = ""

    @State private var recorder: SFSpeechRecognitionService = SFSpeechRecognitionService()
    @State private var speaker = JapaneseSpeaker()

    enum Phase {
        case prompt, recording, transcribing, result, finished
    }

    private var srs: AudioSRSService {
        AudioSRSService(context: modelContext, allExercises: allExercises)
    }

    private var current: AudioQueueItem? {
        guard index < queue.count else { return nil }
        return queue[index]
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        Group {
            if phase == .finished || current == nil {
                finishedView
            } else if let item = current {
                drillBody(item: item)
            }
        }
        .navigationTitle("Audio Drill (\(min(index + 1, queue.count))/\(queue.count))")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            recorder.cancel()
        }
    }

    private func drillBody(item: AudioQueueItem) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                stateBadge(item: item)

                VStack(spacing: 6) {
                    Text(item.exercise.translation)
                        .font(.system(size: scaled(24), weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 8)

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: scaled(13)))
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                switch phase {
                case .prompt:
                    promptControls(item: item)
                case .recording:
                    recordingControls
                case .transcribing:
                    transcribingView
                case .result:
                    resultPanel(item: item)
                case .finished:
                    EmptyView()
                }

                Text(item.exercise.id)
                    .font(.system(size: scaled(10), design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 12)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - State badge

    private func stateBadge(item: AudioQueueItem) -> some View {
        let label: String
        let color: Color
        switch item {
        case .new:
            label = "NEW"; color = .purple
        case .review(let card, _):
            switch card.fsrsStatusRaw {
            case 1: label = "Learning"; color = .orange
            case 2: label = "Review"; color = .blue
            case 3: label = "Relearning"; color = .red
            default: label = "New"; color = .purple
            }
        }
        return Text(label)
            .font(.system(size: scaled(11), weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }

    // MARK: - Phase: prompt

    private func promptControls(item: AudioQueueItem) -> some View {
        VStack(spacing: 16) {
            Button {
                Task { await startRecording() }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 96, height: 96)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .padding(.top, 4)

            Text("Tap to record")
                .font(.system(size: scaled(13)))
                .foregroundColor(.secondary)

            Button {
                markTooEasy(item: item)
            } label: {
                Text("Too easy — skip")
                    .font(.system(size: scaled(15), weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(.accentColor)
                    .cornerRadius(10)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Phase: recording

    private var recordingControls: some View {
        VStack(spacing: 16) {
            Button {
                Task { await stopRecording() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 96, height: 96)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            Text("Recording… tap to stop")
                .font(.system(size: scaled(13)))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Phase: transcribing

    private var transcribingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Transcribing…")
                .font(.system(size: scaled(13)))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Phase: result

    @ViewBuilder
    private func resultPanel(item: AudioQueueItem) -> some View {
        if let result = lastResult {
            VStack(spacing: 14) {
                resultBadge(passed: result.passed)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("Heard:")
                            .font(.system(size: scaled(13), weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(lastRawTranscription.isEmpty ? "—" : lastRawTranscription)
                            .font(.system(size: scaled(15), design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    scoreBar(score: result.bestScore)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                if result.passed {
                    passControls(item: item)
                } else {
                    failControls(item: item)
                }
            }
        }
    }

    private func resultBadge(passed: Bool) -> some View {
        Text(passed ? "PASS" : "FAIL")
            .font(.system(size: scaled(20), weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(passed ? Color.green : Color.red)
            .cornerRadius(10)
    }

    private func scoreBar(score: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Score")
                    .font(.system(size: scaled(13), weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int((score * 100).rounded()))% (threshold \(Int((threshold * 100).rounded()))%)")
                    .font(.system(size: scaled(12)))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemBackground))
                    Capsule()
                        .fill(score >= threshold ? Color.green : Color.orange)
                        .frame(width: max(4, geo.size.width * CGFloat(min(max(score, 0), 1))))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Pass controls

    private func passControls(item: AudioQueueItem) -> some View {
        VStack(spacing: 10) {
            answerCard(item: item)

            Button {
                speaker.speak(item.exercise.exampleSentence)
            } label: {
                Label("Hear it", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: scaled(15), weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            Button {
                applyPass(item: item)
            } label: {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: scaled(18), weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Shared answer card

    private func answerCard(item: AudioQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Target")
                .font(.system(size: scaled(11), weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)
            Text(item.exercise.exampleSentence)
                .font(.system(size: scaled(20), weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Fail controls

    private func failControls(item: AudioQueueItem) -> some View {
        VStack(spacing: 10) {
            answerCard(item: item)

            Button {
                speaker.speak(item.exercise.exampleSentence)
            } label: {
                Label("Hear it again", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: scaled(15), weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            Button {
                speaker.stop()
                resetForAnotherAttempt()
                Task { await startRecording() }
            } label: {
                Label("Try again", systemImage: "mic.fill")
                    .font(.system(size: scaled(18), weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            Button {
                applySkip(item: item)
            } label: {
                Text("Skip and move on")
                    .font(.system(size: scaled(14), weight: .medium))
                    .padding(.vertical, 8)
            }
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Finished

    private var finishedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("Drill complete")
                .font(.system(size: scaled(24), weight: .bold))
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: scaled(17), weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Actions

    private func startRecording() async {
        errorMessage = nil
        if permissionGranted == nil {
            let ok = await recorder.requestAuthorization()
            permissionGranted = ok
            if !ok {
                errorMessage = SpeechRecognitionError.permissionDenied.errorDescription
                return
            }
        } else if permissionGranted == false {
            errorMessage = SpeechRecognitionError.permissionDenied.errorDescription
            return
        }
        do {
            try await recorder.startRecording()
            phase = .recording
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func stopRecording() async {
        guard let item = current else { return }
        phase = .transcribing
        do {
            let t = try await recorder.stopRecordingAndTranscribe()
            lastRawTranscription = t.raw
            lastDurationMs = t.durationMs
            let result = AnswerMatcher.match(
                recognized: t.raw,
                exercise: item.exercise,
                threshold: threshold,
                stripFinalCopula: stripFinalCopula
            )
            lastResult = result
            StudyLog.record(correct: result.passed, context: modelContext)
            let attempt = AudioAttempt(
                exerciseId: item.exercise.id,
                rawTranscription: t.raw,
                normalizedTranscription: result.normalizedRecognition,
                bestMatchKanji: result.bestAnswerKanji,
                matchScore: result.bestScore,
                thresholdUsed: threshold,
                stripFinalCopulaUsed: stripFinalCopula,
                passed: result.passed,
                durationMs: t.durationMs,
                synthetic: false
            )
            modelContext.insert(attempt)
            try? modelContext.save()
            lastAttempt = attempt
            // First real attempt: create the card if needed and stamp introducedAt now,
            // so it counts toward today's new-card budget.
            let card = srs.ensureCard(for: item.exercise)
            srs.markIntroduced(card: card)
            phase = .result
            if !result.passed {
                speaker.speak(item.exercise.exampleSentence)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .prompt
        }
    }

    private func markTooEasy(item: AudioQueueItem) {
        _ = srs.markTooEasy(exercise: item.exercise)
        StudyLog.record(correct: true, context: modelContext)
        let attempt = AudioAttempt(
            exerciseId: item.exercise.id,
            rawTranscription: "<marked too easy>",
            normalizedTranscription: "",
            bestMatchKanji: nil,
            matchScore: 1.0,
            thresholdUsed: threshold,
            stripFinalCopulaUsed: stripFinalCopula,
            passed: true,
            durationMs: 0,
            synthetic: true,
            fsrsGrade: Rating.easy.value
        )
        modelContext.insert(attempt)
        try? modelContext.save()
        advance()
    }

    private func applyPass(item: AudioQueueItem) {
        speaker.stop()
        let card = srs.ensureCard(for: item.exercise)
        srs.grade(card: card, rating: .good)
        if let attempt = lastAttempt {
            attempt.fsrsGrade = Rating.good.value
            try? modelContext.save()
        }
        advance()
    }

    private func applySkip(item: AudioQueueItem) {
        speaker.stop()
        let card = srs.ensureCard(for: item.exercise)
        srs.grade(card: card, rating: .again)
        if let attempt = lastAttempt {
            attempt.fsrsGrade = Rating.again.value
            try? modelContext.save()
        }
        advance()
    }

    private func resetForAnotherAttempt() {
        lastResult = nil
        lastAttempt = nil
        lastRawTranscription = ""
        phase = .prompt
    }

    private func advance() {
        resetForAnotherAttempt()
        index += 1
        if index >= queue.count {
            phase = .finished
        }
    }
}
