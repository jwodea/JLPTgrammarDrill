import SwiftUI
import SwiftData

struct GrammarBrowserView: View {
    @State private var searchText = ""
    @State private var levelFilter = "All"
    @State private var allPoints: [GrammarPoint] = []
    @State private var selectedPoint: GrammarPoint?
    @Query private var srsRecords: [SRSRecord]
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private let levelOptions = ["All", "N3", "N2", "N1"]

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
                            .background(point.level == "N3" ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                            .foregroundColor(point.level == "N3" ? .blue : .orange)
                            .clipShape(Capsule())
                    }
                }
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
                        .background(point.level == "N3" ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                        .foregroundColor(point.level == "N3" ? .blue : .orange)
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
