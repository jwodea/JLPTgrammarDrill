import SwiftUI
import SwiftData

/// Read-only browser of every audio-eligible exercise in the active levels.
struct AudioBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreManager.self) private var store
    @Query private var attempts: [AudioAttempt]

    @AppStorage(AudioDrillSettings.activeLevelsCSVKey)
    private var activeLevelsCSV = AudioDrillSettings.defaultActiveLevelsCSV

    @State private var search = ""
    @State private var showPaywall = false
    @State private var allUnfiltered: [AudioExercise] = []
    @State private var freeIds: Set<String> = []

    private var activeLevels: Set<String> {
        Set(activeLevelsCSV.split(separator: ",").map(String.init))
    }

    private func isLocked(_ id: String) -> Bool {
        !store.isUnlocked && !freeIds.contains(id)
    }

    private var filtered: [AudioExercise] {
        let active = allUnfiltered.filter { activeLevels.contains($0.level) }
        guard !search.isEmpty else { return active }
        let q = search.lowercased()
        return active.filter {
            $0.translation.lowercased().contains(q)
                || $0.exampleSentence.contains(search)
                || $0.hiraganaFull.contains(search)
        }
    }

    private var lastAttemptByExercise: [String: AudioAttempt] {
        var out: [String: AudioAttempt] = [:]
        for a in attempts {
            if let existing = out[a.exerciseId], existing.timestamp > a.timestamp { continue }
            out[a.exerciseId] = a
        }
        return out
    }

    var body: some View {
        List {
            ForEach(filtered, id: \.id) { ex in
                let locked = isLocked(ex.id)
                Button {
                    if locked { showPaywall = true }
                } label: {
                    row(ex, locked: locked)
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $search, prompt: "Search English or Japanese")
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear {
            if allUnfiltered.isEmpty {
                allUnfiltered = AudioExerciseLoader.loadAll()
            }
            freeIds = Entitlement.freeAudioIds(from: allUnfiltered) ?? []
        }
        .onChange(of: store.isUnlocked) {
            freeIds = Entitlement.freeAudioIds(from: allUnfiltered) ?? []
        }
    }

    private func row(_ ex: AudioExercise, locked: Bool) -> some View {
        let last = lastAttemptByExercise[ex.id]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ex.level)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(ex.id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else if let last {
                    Image(systemName: last.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(last.passed ? .green : .red)
                    Text(last.timestamp.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Text(ex.translation)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(locked ? .secondary : .primary)
            if !locked {
                Text(ex.exampleSentence)
                    .font(.system(size: 14))
                Text(ex.hiraganaFull)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if !ex.audioAlternatives.isEmpty {
                    ForEach(ex.audioAlternatives, id: \.self) { alt in
                        Text("· \(alt.kanji)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
