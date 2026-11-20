import SwiftUI
import SwiftData
import SwiftFSRS

struct GrammarBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreManager.self) private var store
    @State private var searchText = ""
    @State private var levelFilter = "All"
    @State private var allPoints: [GrammarPoint] = []
    @State private var freeIds: Set<String> = []
    @State private var selectedPoint: GrammarPoint?
    @State private var showPaywall = false
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @Query private var srsRecords: [SRSRecord]
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func isLocked(_ id: String) -> Bool {
        !store.isUnlocked && !freeIds.contains(id)
    }

    private let levelOptions = ["All", "N5", "N4", "N3", "N2", "N1"]

    private var filteredPoints: [GrammarPoint] {
        allPoints.filter { point in
            let matchesLevel = levelFilter == "All" || point.level == levelFilter
            let matchesSearch = searchText.isEmpty ||
                point.pattern.localizedCaseInsensitiveContains(searchText) ||
                point.meaning.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    private func levelBadgeColor(_ level: String) -> Color {
        switch level {
        case "N5": return .green
        case "N4": return .teal
        case "N3": return .blue
        case "N2": return .orange
        case "N1": return .red
        default: return .secondary
        }
    }

    /// Per-row mastery indicator matching the discrete buckets shown in the Stats card.
    private struct MasteryIndicator {
        let icon: String
        let color: Color
    }

    /// Index records once per body invalidation so per-row mastery lookups are
    /// O(1). With ~525 patterns × ~525 records, the old `.first(where:)` scan
    /// was effectively O(n²) per render.
    private var srsRecordsById: [String: SRSRecord] {
        Dictionary(uniqueKeysWithValues: srsRecords.map { ($0.grammarId, $0) })
    }

    private func masteryIndicator(for grammarId: String, recordsById: [String: SRSRecord]) -> MasteryIndicator {
        guard let record = recordsById[grammarId] else {
            return MasteryIndicator(icon: "sparkles", color: .secondary) // Unseen
        }
        let days = record.fsrsScheduledDays
        if days >= 60 {
            return MasteryIndicator(icon: "crown", color: .yellow) // Mastered
        } else if days >= 14 {
            return MasteryIndicator(icon: "star", color: .purple) // Confident
        } else if days >= 3 {
            return MasteryIndicator(icon: "book.closed", color: .blue) // Familiar
        } else {
            return MasteryIndicator(icon: "flame", color: .orange) // Learning
        }
    }

    /// Smooth orange→green tint for a row, based on SRS scheduled days
    /// clamped to a 0–60 day window. Unseen rows get the default background.
    private func masteryRowTint(for grammarId: String, recordsById: [String: SRSRecord]) -> Color {
        guard let record = recordsById[grammarId] else {
            return Theme.card
        }
        let progress = min(max(Double(record.fsrsScheduledDays) / 60.0, 0.0), 1.0)
        let hue = 0.083 + progress * (0.333 - 0.083) // orange (30°) → green (120°)
        return Color(hue: hue, saturation: 0.8, brightness: 1.0).opacity(0.18)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Every grammar pattern tested in the drills.")
                .font(.system(size: scaled(13)))
                .foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 10)

            Picker("Level", selection: $levelFilter) {
                ForEach(levelOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            let recordsById = srsRecordsById
            List(filteredPoints) { point in
                let locked = isLocked(point.id)
                Button {
                    if locked {
                        showPaywall = true
                    } else if isSelecting {
                        toggleSelection(point.id)
                    } else {
                        selectedPoint = point
                    }
                } label: {
                    HStack {
                        if isSelecting {
                            Image(systemName: selectedIds.contains(point.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIds.contains(point.id) ? Theme.brand : Theme.inkMuted)
                                .font(.system(size: scaled(22)))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.pattern)
                                .font(.system(size: scaled(18), weight: .bold))
                                .foregroundStyle(locked ? Theme.inkMuted : Theme.ink)
                            Text(point.meaning)
                                .font(.system(size: scaled(15)))
                                .foregroundStyle(Theme.inkMuted)
                        }

                        Spacer()

                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: scaled(13)))
                                .foregroundStyle(Theme.inkMuted)
                                .frame(width: 18)
                        } else {
                            let mastery = masteryIndicator(for: point.id, recordsById: recordsById)
                            Image(systemName: mastery.icon)
                                .font(.system(size: scaled(13)))
                                .foregroundColor(mastery.color)
                                .frame(width: 18)
                        }

                        Text(point.level)
                            .font(.system(size: scaled(13), weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(levelBadgeColor(point.level).opacity(0.15))
                            .foregroundColor(levelBadgeColor(point.level))
                            .clipShape(Capsule())
                    }
                }
                .contextMenu {
                    if !locked {
                        if recordsById[point.id] != nil {
                            Button {
                                resetProgress(for: point.id)
                            } label: {
                                Label("Reset Progress", systemImage: "arrow.counterclockwise")
                            }
                        }
                        Button {
                            markAsKnown(grammarId: point.id)
                        } label: {
                            Label("Mark as Known", systemImage: "checkmark.seal.fill")
                        }
                    }
                }
                .listRowBackground(locked ? Theme.card : masteryRowTint(for: point.id, recordsById: recordsById))
            }
            .scrollContentBackground(.hidden)

            if isSelecting {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        Button {
                            let visibleIds = Set(filteredPoints.map(\.id).filter { !isLocked($0) })
                            if visibleIds.isSubset(of: selectedIds) {
                                selectedIds.subtract(visibleIds)
                            } else {
                                selectedIds.formUnion(visibleIds)
                            }
                        } label: {
                            let allVisible = Set(filteredPoints.map(\.id).filter { !isLocked($0) }).isSubset(of: selectedIds)
                            Text(allVisible ? "Deselect All" : "Select All")
                                .font(.system(size: scaled(15), weight: .medium))
                        }
                        .buttonStyle(TactileSecondaryButtonStyle())

                        Button {
                            for id in selectedIds {
                                markAsKnown(grammarId: id)
                            }
                            selectedIds.removeAll()
                            isSelecting = false
                        } label: {
                            Text("Mark \(selectedIds.count) Known")
                                .font(.system(size: scaled(15), weight: .medium))
                                .foregroundStyle(selectedIds.isEmpty ? Theme.inkMuted : Theme.correct)
                        }
                        .buttonStyle(TactileSecondaryButtonStyle())
                        .disabled(selectedIds.isEmpty)

                        Button {
                            for id in selectedIds {
                                resetProgress(for: id)
                            }
                            selectedIds.removeAll()
                            isSelecting = false
                        } label: {
                            Text("Reset \(selectedIds.count)")
                                .font(.system(size: scaled(15), weight: .medium))
                                .foregroundStyle(selectedIds.isEmpty ? Theme.inkMuted : Theme.incorrect)
                        }
                        .buttonStyle(TactileSecondaryButtonStyle())
                        .disabled(selectedIds.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            }
        }
        .background(TactileBackdrop().ignoresSafeArea())
        .searchable(text: $searchText, prompt: "Search patterns or meanings")
        .navigationTitle("Grammar List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting {
                        selectedIds.removeAll()
                    }
                }
            }
        }
        .sheet(item: $selectedPoint) { point in
            GrammarDetailView(
                point: point,
                record: srsRecordsById[point.id],
                onMarkKnown: { markAsKnown(grammarId: point.id) },
                onReset: { resetProgress(for: point.id) }
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear {
            if allPoints.isEmpty {
                allPoints = GrammarLoader.loadAll()
            }
            freeIds = Entitlement.freeGrammarIds(from: GrammarLoader.allPatternFiles) ?? []
        }
        .onChange(of: store.isUnlocked) {
            freeIds = Entitlement.freeGrammarIds(from: GrammarLoader.allPatternFiles) ?? []
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func markAsKnown(grammarId: String) {
        SRSEngine.markKnown(grammarId: grammarId, context: modelContext)
    }

    private func resetProgress(for grammarId: String) {
        let descriptor = FetchDescriptor<SRSRecord>(
            predicate: #Predicate { $0.grammarId == grammarId }
        )
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(record)
        try? modelContext.save()
    }
}

struct GrammarDetailView: View {
    let point: GrammarPoint
    let record: SRSRecord?
    var onMarkKnown: () -> Void = {}
    var onReset: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private var srsStatus: String {
        guard let record else {
            return "New"
        }
        let due = record.fsrsDue
        let now = Date.now
        if due <= now {
            return "Due for review"
        }
        let days = Calendar.current.dateComponents([.day], from: now, to: due).day ?? 0
        if days == 0 {
            return "Due later today"
        }
        return "Next review in \(days) day\(days == 1 ? "" : "s")"
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    private func detailLevelBadgeColor(_ level: String) -> Color {
        switch level {
        case "N5": return .green
        case "N4": return .teal
        case "N3": return .blue
        case "N2": return .orange
        case "N1": return .red
        default: return .secondary
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(point.pattern)
                        .font(.system(size: scaled(30), weight: .bold))

                    Text(point.level)
                        .font(.system(size: scaled(13), weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(detailLevelBadgeColor(point.level).opacity(0.15))
                        .foregroundColor(detailLevelBadgeColor(point.level))
                        .clipShape(Capsule())
                }

                Text(point.meaning)
                    .font(.system(size: scaled(18)))
                    .foregroundStyle(Theme.inkMuted)

                Divider()

                Text(point.exampleSentence)
                    .font(.system(size: scaled(19)))

                Text(point.translation)
                    .font(.system(size: scaled(16)))
                    .foregroundStyle(Theme.inkMuted)

                Divider()

                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(Theme.inkMuted)
                    Text(srsStatus)
                        .font(.system(size: scaled(16)))
                        .foregroundStyle(Theme.inkMuted)
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        onMarkKnown()
                        dismiss()
                    } label: {
                        Label("Mark as Known", systemImage: "checkmark.seal.fill")
                            .font(.system(size: scaled(15), weight: .medium))
                            .foregroundStyle(Theme.correct)
                    }
                    .buttonStyle(TactileSecondaryButtonStyle())

                    if record != nil {
                        Button {
                            onReset()
                            dismiss()
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.system(size: scaled(15), weight: .medium))
                                .foregroundStyle(Theme.incorrect)
                        }
                        .buttonStyle(TactileSecondaryButtonStyle())
                    }
                }

                Spacer()
            }
            .padding()
            .background(TactileBackdrop().ignoresSafeArea())
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
