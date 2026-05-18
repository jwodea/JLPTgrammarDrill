import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Chronological list of exercises with at least one audio attempt.
struct AudioHistoryView: View {
    let allExercises: [AudioExercise]

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioAttempt.timestamp, order: .reverse)
    private var attempts: [AudioAttempt]

    @State private var search = ""

    private var byExercise: [(AudioExercise, [AudioAttempt])] {
        let grouped = Dictionary(grouping: attempts, by: \.exerciseId)
        var result: [(AudioExercise, [AudioAttempt])] = []
        for ex in allExercises {
            guard let attemptsForEx = grouped[ex.id], !attemptsForEx.isEmpty else { continue }
            result.append((ex, attemptsForEx.sorted { $0.timestamp > $1.timestamp }))
        }
        return result.sorted { (a, b) in
            (a.1.first?.timestamp ?? .distantPast) > (b.1.first?.timestamp ?? .distantPast)
        }
    }

    private var filtered: [(AudioExercise, [AudioAttempt])] {
        guard !search.isEmpty else { return byExercise }
        let q = search.lowercased()
        return byExercise.filter { ex, _ in
            ex.translation.lowercased().contains(q) || ex.exampleSentence.contains(search)
        }
    }

    var body: some View {
        List {
            ForEach(filtered, id: \.0.id) { ex, attemptList in
                NavigationLink {
                    AudioHistoryDetailView(exercise: ex, attempts: attemptList)
                } label: {
                    AudioHistoryRow(exercise: ex, attempts: attemptList)
                }
            }
        }
        .searchable(text: $search, prompt: "Search English or Japanese")
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No attempts yet",
                    systemImage: "mic.slash",
                    description: Text("Record an answer in the drill to start building history.")
                )
            }
        }
    }
}

private struct AudioHistoryRow: View {
    let exercise: AudioExercise
    let attempts: [AudioAttempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.translation)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(2)
            HStack(spacing: 8) {
                if let last = attempts.first {
                    Text(last.timestamp.formatted(.relative(presentation: .named)))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Image(systemName: last.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(last.passed ? .green : .red)
                }
                Text("\(attempts.count) attempt\(attempts.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Detail

struct AudioHistoryDetailView: View {
    let exercise: AudioExercise
    let attempts: [AudioAttempt]

    @State private var exportURL: URL?
    @State private var showShare = false

    var body: some View {
        List {
            Section("Sentence") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.exampleSentence).font(.system(size: 18, weight: .semibold))
                    Text(exercise.hiraganaFull).font(.system(size: 14)).foregroundColor(.secondary)
                    Text(exercise.translation).font(.system(size: 14)).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Attempts (\(attempts.count))") {
                ForEach(attempts, id: \.id) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(a.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Spacer()
                            if a.synthetic {
                                Text("TOO EASY").font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.purple)
                            } else {
                                Text(a.passed ? "PASS" : "FAIL")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(a.passed ? .green : .red)
                            }
                            Text("\(Int((a.matchScore * 100).rounded()))%")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                            Text("@\(Int((a.thresholdUsed * 100).rounded()))%")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Text("Raw: \(a.rawTranscription)")
                            .font(.system(size: 13, design: .monospaced))
                        if !a.normalizedTranscription.isEmpty {
                            Text("Norm: \(a.normalizedTranscription)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        if let g = a.fsrsGrade {
                            Text("Grade: \(gradeLabel(g))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportAsJSON()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func gradeLabel(_ g: Int) -> String {
        switch g {
        case 1: return "Again"
        case 2: return "Hard"
        case 3: return "Good"
        case 4: return "Easy"
        default: return "?"
        }
    }

    private func exportAsJSON() {
        struct Export: Encodable {
            let exerciseId: String
            let exampleSentence: String
            let translation: String
            let attempts: [Item]
            struct Item: Encodable {
                let id: String
                let timestamp: Date
                let rawTranscription: String
                let normalizedTranscription: String
                let bestMatchKanji: String?
                let matchScore: Double
                let thresholdUsed: Double
                let stripFinalCopulaUsed: Bool
                let passed: Bool
                let fsrsGrade: Int?
                let durationMs: Int
                let synthetic: Bool
            }
        }
        let payload = Export(
            exerciseId: exercise.id,
            exampleSentence: exercise.exampleSentence,
            translation: exercise.translation,
            attempts: attempts.map {
                .init(id: $0.id.uuidString,
                      timestamp: $0.timestamp,
                      rawTranscription: $0.rawTranscription,
                      normalizedTranscription: $0.normalizedTranscription,
                      bestMatchKanji: $0.bestMatchKanji,
                      matchScore: $0.matchScore,
                      thresholdUsed: $0.thresholdUsed,
                      stripFinalCopulaUsed: $0.stripFinalCopulaUsed,
                      passed: $0.passed,
                      fsrsGrade: $0.fsrsGrade,
                      durationMs: $0.durationMs,
                      synthetic: $0.synthetic)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(exercise.id)-attempts.json")
        try? data.write(to: url, options: .atomic)
        exportURL = url
        showShare = true
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
