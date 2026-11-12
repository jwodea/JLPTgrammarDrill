import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    /// Which drill's stats to show. Each drill page opens its own variant.
    enum Kind {
        case grammar, particles, audio

        var title: String {
            switch self {
            case .grammar: return "Grammar Stats"
            case .particles: return "Particle Stats"
            case .audio: return "Audio Stats"
            }
        }
    }

    var kind: Kind = .grammar

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
    @State private var activityRange: ActivityRange = .week

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

    // MARK: - Study time activity

    /// Bars for the selected range. Short ranges bucket by day (plotted in
    /// minutes); long ranges bucket by month (plotted in hours).
    private var activitySeries: (buckets: [ActivityBucket], unit: Calendar.Component) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch activityRange {
        case .week:
            return (dailyBuckets(days: 7, endingAt: today), .day)
        case .month:
            return (dailyBuckets(days: 30, endingAt: today), .day)
        case .year:
            let thisMonth = calendar.dateInterval(of: .month, for: today)!.start
            let start = calendar.date(byAdding: .month, value: -11, to: thisMonth)!
            return (monthlyBuckets(from: start, through: today), .month)
        case .all:
            // studyLogs is sorted by dateKey, so the first entry is the earliest day.
            guard let first = studyLogs.first?.date else {
                return (dailyBuckets(days: 7, endingAt: today), .day)
            }
            let span = calendar.dateComponents([.day], from: first, to: today).day ?? 0
            if span < 30 {
                return (dailyBuckets(days: max(span + 1, 7), endingAt: today), .day)
            }
            return (monthlyBuckets(from: first, through: today), .month)
        }
    }

    private func dailyBuckets(days: Int, endingAt today: Date) -> [ActivityBucket] {
        let calendar = Calendar.current
        let secondsByKey = Dictionary(studyLogs.map { ($0.dateKey, $0.secondsStudied) }, uniquingKeysWith: +)
        return (0..<days).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            return ActivityBucket(date: date, seconds: secondsByKey[StudyLog.key(for: date)] ?? 0)
        }
    }

    private func monthlyBuckets(from start: Date, through end: Date) -> [ActivityBucket] {
        let calendar = Calendar.current
        let monthStart = { (date: Date) in calendar.dateInterval(of: .month, for: date)!.start }
        let secondsByMonth = Dictionary(studyLogs.map { (monthStart($0.date), $0.secondsStudied) }, uniquingKeysWith: +)

        var buckets: [ActivityBucket] = []
        var month = monthStart(start)
        let last = monthStart(end)
        while month <= last {
            buckets.append(ActivityBucket(date: month, seconds: secondsByMonth[month] ?? 0))
            month = calendar.date(byAdding: .month, value: 1, to: month)!
        }
        return buckets
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
                switch kind {
                case .grammar:
                    grammarSection
                    activityChart
                case .particles:
                    particleSection
                case .audio:
                    audioSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(GlassBackdrop().ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Only load the bundle data this variant actually displays.
            switch kind {
            case .grammar where grammarPoints.isEmpty:
                grammarPoints = GrammarLoader.loadAll()
            case .audio where audioExercises.isEmpty:
                audioExercises = AudioExerciseLoader.loadAll()
            case .particles where particleExercises.isEmpty:
                particleExercises = ParticleLoader.loadAll()
            default:
                break
            }
        }
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
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
        let series = activitySeries
        let isDaily = series.unit == .day
        // Daily bars read naturally in minutes; monthly totals in hours.
        let divisor: Double = isDaily ? 60 : 3600
        let unitLabel = isDaily ? "min" : "hr"
        let totalHours = series.buckets.reduce(0) { $0 + $1.seconds } / 3600
        let maxValue = (series.buckets.map(\.seconds).max() ?? 0) / divisor

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader(title: "Study Time", subtitle: activityRange.subtitle)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f h", totalHours))
                        .font(.system(size: scaled(18), weight: .semibold))
                        .monospacedDigit()
                    Text("total")
                        .font(.system(size: scaled(12)))
                        .foregroundColor(.secondary)
                }
            }

            Picker("Range", selection: $activityRange) {
                ForEach(ActivityRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Chart(series.buckets) { bucket in
                BarMark(
                    x: .value("Date", bucket.date, unit: series.unit),
                    y: .value("Time", bucket.seconds / divisor)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(isDaily && series.buckets.count > 14 ? 2 : 4)
            }
            .chartYScale(domain: 0...max(maxValue * 1.15, isDaily ? 10 : 1))
            .chartYAxisLabel(unitLabel)
            .chartXAxis {
                switch activityRange {
                case .week:
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                case .month:
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                case .year:
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    }
                case .all:
                    AxisMarks()
                }
            }
            .frame(height: 160)
            .animation(.easeInOut(duration: 0.25), value: activityRange)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Supporting Types

private enum ActivityRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All"

    var id: Self { self }

    var subtitle: String {
        switch self {
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .year: return "Last 12 months"
        case .all: return "All time"
        }
    }
}

private struct ActivityBucket: Identifiable {
    let date: Date
    let seconds: Double
    var id: Date { date }
}

#Preview {
    NavigationStack {
        StatsView()
    }
    .modelContainer(for: [SRSRecord.self, StudyLog.self, AudioCard.self, AudioAttempt.self], inMemory: true)
}
