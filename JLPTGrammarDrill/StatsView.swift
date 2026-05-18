import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \StudyLog.dateKey) private var studyLogs: [StudyLog]
    @Query private var srsRecords: [SRSRecord]
    @Query private var audioCards: [AudioCard]
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    // Bundle-derived data is invariant for the lifetime of the app. Cache it in
    // @State and populate once via `.onAppear` so SwiftUI body re-evaluation
    // (triggered by any @Query change) doesn't re-run the loaders.
    @State private var grammarPoints: [GrammarPoint] = []
    @State private var audioExercises: [AudioExercise] = []
    @State private var particleExercises: [ParticleExercise] = []

    private static let levels = ["N5", "N4", "N3", "N2", "N1"]

    /// Traffic-light mastery palette — reads as "weak to strong" at a glance.
    private enum MasteryColor {
        static let unseen    = Color(.tertiarySystemFill)
        static let learning  = Color(.systemRed)
        static let familiar  = Color(.systemOrange)
        static let confident = Color(.systemYellow)
        static let mastered  = Color(.systemGreen)
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    // MARK: - Data model

    private struct MasteryCounts {
        var unseen: Int = 0
        var learning: Int = 0
        var familiar: Int = 0
        var confident: Int = 0
        var mastered: Int = 0
        var total: Int { unseen + learning + familiar + confident + mastered }
        var studied: Int { learning + familiar + confident + mastered }
    }

    private static func bucket(forScheduledDays days: Double) -> WritableKeyPath<MasteryCounts, Int> {
        if days >= 60 { return \.mastered }
        if days >= 14 { return \.confident }
        if days >= 3  { return \.familiar }
        return \.learning
    }

    // MARK: - Grammar (per JLPT level)

    private var grammarMasteryByLevel: [String: MasteryCounts] {
        var out = Dictionary(uniqueKeysWithValues: Self.levels.map { ($0, MasteryCounts()) })
        for level in Self.levels {
            out[level]!.unseen = grammarPoints.filter { $0.level == level }.count
        }
        for record in srsRecords where !record.grammarId.hasPrefix("part_") {
            let level = level(fromId: record.grammarId)
            guard var counts = out[level] else { continue }
            if counts.unseen > 0 { counts.unseen -= 1 }
            counts[keyPath: Self.bucket(forScheduledDays: record.fsrsScheduledDays)] += 1
            out[level] = counts
        }
        return out
    }

    // MARK: - Audio (per JLPT level)

    private var audioMasteryByLevel: [String: MasteryCounts] {
        var out = Dictionary(uniqueKeysWithValues: Self.levels.map { ($0, MasteryCounts()) })
        for level in Self.levels {
            out[level]!.unseen = audioExercises.filter { $0.level == level }.count
        }
        for card in audioCards {
            let level = level(fromId: card.exerciseId)
            guard var counts = out[level] else { continue }
            if counts.unseen > 0 { counts.unseen -= 1 }
            counts[keyPath: Self.bucket(forScheduledDays: card.fsrsScheduledDays)] += 1
            out[level] = counts
        }
        return out
    }

    private var audioInRotation: Int {
        audioCards.filter { $0.introducedAt != nil }.count
    }

    // MARK: - Particles (per particle)

    /// Returns particles sorted by total exercise count (descending), each paired with its mastery counts.
    private var particleMastery: [(particle: String, counts: MasteryCounts)] {
        let particleById = Dictionary(uniqueKeysWithValues: particleExercises.map { ($0.id, $0.particle) })

        var counts: [String: MasteryCounts] = [:]
        for ex in particleExercises {
            counts[ex.particle, default: MasteryCounts()].unseen += 1
        }
        for record in srsRecords where record.grammarId.hasPrefix("part_") {
            guard let particle = particleById[record.grammarId],
                  var c = counts[particle] else { continue }
            if c.unseen > 0 { c.unseen -= 1 }
            c[keyPath: Self.bucket(forScheduledDays: record.fsrsScheduledDays)] += 1
            counts[particle] = c
        }
        return counts
            .map { (particle: $0.key, counts: $0.value) }
            .sorted { ($0.counts.total, $0.particle) > ($1.counts.total, $1.particle) }
    }

    // MARK: - Streak and daily activity

    private var currentStreak: Int {
        let calendar = Calendar.current
        let activeKeys = Set(studyLogs.filter { $0.itemsStudied > 0 }.map(\.dateKey))
        guard !activeKeys.isEmpty else { return 0 }

        var date = calendar.startOfDay(for: Date())
        if !activeKeys.contains(StudyLog.key(for: date)) {
            date = calendar.date(byAdding: .day, value: -1, to: date)!
            if !activeKeys.contains(StudyLog.key(for: date)) { return 0 }
        }

        var count = 0
        while activeKeys.contains(StudyLog.key(for: date)) {
            count += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    private var last14Days: [DayEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let logsByKey = Dictionary(uniqueKeysWithValues: studyLogs.map { ($0.dateKey, $0) })

        return (0..<14).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let log = logsByKey[StudyLog.key(for: date)]
            return DayEntry(date: date, studied: log?.itemsStudied ?? 0)
        }
    }

    private func level(fromId id: String) -> String {
        // Both grammar ("n1_001") and audio ("n5_001_1") ids share the same prefix scheme.
        guard let underscore = id.firstIndex(of: "_") else { return "" }
        return id[..<underscore].uppercased()
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                streakBanner
                grammarSection
                particleSection
                audioSection
                activityChart
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if grammarPoints.isEmpty {
                grammarPoints = GrammarLoader.loadAll()
            }
            if audioExercises.isEmpty {
                audioExercises = AudioExerciseLoader.loadAll()
            }
            if particleExercises.isEmpty {
                particleExercises = ParticleLoader.loadAll()
            }
        }
    }

    // MARK: - Streak banner

    private var streakBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: scaled(20)))
                .foregroundColor(.red)
            Text("\(currentStreak)")
                .font(.system(size: scaled(20), weight: .bold))
            Text("day streak")
                .font(.system(size: scaled(14)))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Grammar section

    private var grammarSection: some View {
        let data = grammarMasteryByLevel
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Grammar Mastery", subtitle: "By JLPT level")

            VStack(spacing: 10) {
                ForEach(Self.levels, id: \.self) { level in
                    if let counts = data[level] {
                        masteryRow(label: level, counts: counts, labelWidth: 28)
                    }
                }
            }

            masteryLegend

            Text("Levels by FSRS review interval: Learning <3d · Familiar 3–14d · Confident 14–60d · Mastered ≥60d.")
                .font(.system(size: scaled(11)))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Particles section

    private var particleSection: some View {
        let data = particleMastery
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Particles Mastery", subtitle: "By particle")

            VStack(spacing: 10) {
                ForEach(data, id: \.particle) { entry in
                    masteryRow(label: entry.particle, counts: entry.counts, labelWidth: 36)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Audio section

    private var audioSection: some View {
        let data = audioMasteryByLevel
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Audio Mastery", subtitle: "Spoken sentences by JLPT level")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(audioInRotation)")
                    .font(.system(size: scaled(22), weight: .bold))
                Text(audioInRotation == 1 ? "sentence in rotation" : "sentences in rotation")
                    .font(.system(size: scaled(13)))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(Self.levels, id: \.self) { level in
                    if let counts = data[level] {
                        masteryRow(label: level, counts: counts, labelWidth: 28)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Row + legend helpers

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: scaled(18), weight: .semibold))
            Text(subtitle)
                .font(.system(size: scaled(12)))
                .foregroundColor(.secondary)
        }
    }

    private func masteryRow(label: String, counts: MasteryCounts, labelWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: scaled(14), weight: .semibold))
                .frame(width: labelWidth, alignment: .leading)
                .foregroundColor(.primary)

            masteryBar(counts: counts)
                .frame(height: 14)

            Text("\(counts.studied)/\(counts.total)")
                .font(.system(size: scaled(11), design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func masteryBar(counts: MasteryCounts) -> some View {
        let segments: [(Int, Color)] = [
            (counts.unseen,    MasteryColor.unseen),
            (counts.learning,  MasteryColor.learning),
            (counts.familiar,  MasteryColor.familiar),
            (counts.confident, MasteryColor.confident),
            (counts.mastered,  MasteryColor.mastered)
        ]
        let total = max(counts.total, 1)
        return GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let (count, color) = segment
                    if count > 0 {
                        Rectangle()
                            .fill(color)
                            .frame(width: max(geo.size.width * CGFloat(count) / CGFloat(total) - 1, 1))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private var masteryLegend: some View {
        let items: [(String, Color)] = [
            ("Unseen",    MasteryColor.unseen),
            ("Learning",  MasteryColor.learning),
            ("Familiar",  MasteryColor.familiar),
            ("Confident", MasteryColor.confident),
            ("Mastered",  MasteryColor.mastered)
        ]
        return HStack(spacing: 10) {
            ForEach(items, id: \.0) { label, color in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 10, height: 10)
                    Text(label)
                        .font(.system(size: scaled(11)))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Activity chart

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(title: "Daily Activity", subtitle: "Last 14 days")

            let entries = last14Days
            let maxStudied = entries.map(\.studied).max() ?? 1

            Chart(entries) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Studied", entry.studied)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartYScale(domain: 0...(max(maxStudied + 2, 5)))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 160)
            .padding(.top, 6)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Supporting Types

private struct DayEntry: Identifiable {
    let date: Date
    let studied: Int
    var id: Date { date }
}
