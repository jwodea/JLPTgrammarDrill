import SwiftUI
import SwiftData

struct GrammarBrowserView: View {
    @State private var searchText = ""
    @State private var levelFilter = "All"
    @State private var allPoints: [GrammarPoint] = []
    @State private var selectedPoint: GrammarPoint?
    @Query private var srsRecords: [SRSRecord]
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

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

    /// Computes mastery progress (0.0 to 1.0) from SRS scheduled days.
    private func masteryProgress(for grammarId: String) -> Double? {
        guard let record = srsRecords.first(where: { $0.grammarId == grammarId }) else {
            return nil // unseen
        }
        return min(max(Double(record.fsrsScheduledDays) / 60.0, 0.0), 1.0)
    }

    /// Returns a color interpolated from orange (novice) to green (mastered).
    private func masteryHue(for progress: Double) -> Double {
        // Orange hue ≈ 0.083 (30°), Green hue ≈ 0.333 (120°)
        0.083 + progress * (0.333 - 0.083)
    }

    /// Returns a subtle mastery-based tint for the list row background.
    private func masteryRowTint(for grammarId: String) -> Color {
        guard let progress = masteryProgress(for: grammarId) else {
            return Color(.systemBackground) // unseen — default
        }
        return Color(hue: masteryHue(for: progress), saturation: 0.8, brightness: 1.0)
            .opacity(0.18)
    }

    /// Returns a mastery indicator dot color.
    private func masteryColor(for grammarId: String) -> Color {
        guard let progress = masteryProgress(for: grammarId) else {
            return Color(.systemGray4) // unseen
        }
        return Color(hue: masteryHue(for: progress), saturation: 0.8, brightness: 0.85)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Level", selection: $levelFilter) {
                ForEach(levelOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            List(filteredPoints) { point in
                Button {
                    selectedPoint = point
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.pattern)
                                .font(.system(size: scaled(18), weight: .bold))
                                .foregroundColor(.primary)
                            Text(point.meaning)
                                .font(.system(size: scaled(15)))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(point.level)
                            .font(.system(size: scaled(13), weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(levelBadgeColor(point.level).opacity(0.15))
                            .foregroundColor(levelBadgeColor(point.level))
                            .clipShape(Capsule())
                    }
                }
                .listRowBackground(masteryRowTint(for: point.id))
            }
        }
        .searchable(text: $searchText, prompt: "Search patterns or meanings")
        .navigationTitle("Grammar")
        .sheet(item: $selectedPoint) { point in
            GrammarDetailView(point: point, srsRecords: srsRecords)
        }
        .onAppear {
            if allPoints.isEmpty {
                allPoints = GrammarLoader.loadAll()
            }
        }
    }
}

struct GrammarDetailView: View {
    let point: GrammarPoint
    let srsRecords: [SRSRecord]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private var srsStatus: String {
        guard let record = srsRecords.first(where: { $0.grammarId == point.id }) else {
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
                    .foregroundColor(.secondary)

                Divider()

                Text(point.exampleSentence)
                    .font(.system(size: scaled(19)))

                Text(point.translation)
                    .font(.system(size: scaled(16)))
                    .foregroundColor(.secondary)

                Divider()

                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text(srsStatus)
                        .font(.system(size: scaled(16)))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
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
