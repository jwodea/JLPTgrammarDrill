import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreManager.self) private var store
    @Query private var srsRecords: [SRSRecord]
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale
    @AppStorage(SessionBuilder.defaultNewCountKey) private var defaultNewCount = SessionBuilder.defaultNewCount
    @AppStorage(SettingsView.enabledLevelsKey) private var enabledLevelsString = SettingsView.defaultEnabledLevels
    @AppStorage(SettingsView.combinedDrillsKey) private var combinedDrills = false
    @AppStorage(DailyPlanner.dailyGoalKey) private var dailyGoal = DailyPlanner.defaultDailyGoal
    @State private var showPaywall = false

    @State private var grammarPoints: [GrammarPoint] = []
    @State private var particleExercises: [ParticleExercise] = []
    @State private var exercisePool: [String: [SessionExercise]] = [:]
    @State private var sessionItems: [SessionExercise]?
    // Grammar IDs being introduced for the first time in the current session —
    // ExerciseView shows an intro card before each one's first question.
    @State private var newPatternIds: Set<String> = []
    @State private var isLoading = false
    @State private var showAllCaughtUp = false
    @State private var navigateToExercise = false
    @State private var activeKind: SessionKind = .today

    /// What a session is for; decides its size and what "Keep Going" continues with.
    private enum SessionKind {
        /// Due reviews plus a chunk of today's planned new patterns.
        case today
        case reviewOnly
        /// New patterns beyond today's plan, at the learner's request.
        case extraNew
        /// Nothing due: practice the patterns most likely to be slipping.
        case strengthen
    }


    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    // MARK: - Mastery Level Computation

    private enum MasteryLevel: String, CaseIterable {
        case new = "Unseen"
        case learning = "Learning"
        case familiar = "Familiar"
        case confident = "Confident"
        case mastered = "Mastered"

        var icon: String {
            switch self {
            case .new: return "sparkles"
            case .learning: return "flame"
            case .familiar: return "book.closed"
            case .confident: return "star"
            case .mastered: return "crown"
            }
        }

        var color: Color {
            switch self {
            case .new: return .secondary
            case .learning: return .orange
            case .familiar: return .blue
            case .confident: return .purple
            case .mastered: return .yellow
            }
        }

        static func level(for record: SRSRecord) -> MasteryLevel {
            if record.fsrsScheduledDays >= 60 {
                return .mastered
            } else if record.fsrsScheduledDays >= 14 {
                return .confident
            } else if record.fsrsScheduledDays >= 3 {
                return .familiar
            } else {
                return .learning
            }
        }
    }

    private static let allLevels = ["N5", "N4", "N3", "N2", "N1"]

    private var enabledLevelsSet: Set<String> {
        Set(enabledLevelsString.split(separator: ",").map(String.init))
    }

    private func toggleLevel(_ level: String) {
        var current = enabledLevelsSet
        if current.contains(level) {
            // Don't allow disabling all levels.
            if current.count > 1 {
                current.remove(level)
            }
        } else {
            current.insert(level)
        }
        enabledLevelsString = Self.allLevels.filter { current.contains($0) }.joined(separator: ",")
    }

    private var activeGrammarPoints: [GrammarPoint] {
        let levels = enabledLevelsSet
        return grammarPoints.filter { levels.contains($0.level) }
    }

    private var masteryCounts: [MasteryLevel: Int] {
        var counts: [MasteryLevel: Int] = [:]
        for level in MasteryLevel.allCases {
            counts[level] = 0
        }

        let activeIds = Set(activeGrammarPoints.map(\.id))
        let activeRecords = srsRecords.filter { activeIds.contains($0.grammarId) }
        let seenIds = Set(activeRecords.map(\.grammarId))
        counts[.new] = activeGrammarPoints.count - seenIds.count

        for record in activeRecords {
            let level = MasteryLevel.level(for: record)
            counts[level, default: 0] += 1
        }

        return counts
    }

    // MARK: - Daily Plan

    /// Today's plan. Only meaningful once grammar data has loaded — computing it
    /// earlier would cache an allowance based on no active patterns.
    private var dailyPlan: DailyPlan? {
        guard !grammarPoints.isEmpty else { return nil }
        _ = dailyGoal // Re-plan when the goal changes in Settings.
        return DailyPlanner.plan(
            records: srsRecords,
            activeIds: Set(activeGrammarPoints.map(\.id)),
            context: modelContext
        )
    }

    private var unseenCount: Int {
        masteryCounts[.new] ?? 0
    }

    /// New patterns still to introduce today, limited to what's left unseen.
    private var newLeftToday: Int {
        min(dailyPlan?.newRemaining ?? 0, unseenCount)
    }

    /// New patterns for the next "Today's Session": today's remainder, in chunks
    /// of the per-session size from Settings.
    private var todayNewCount: Int {
        min(newLeftToday, defaultNewCount)
    }

    private var hasWorkToday: Bool {
        sessionStats.newCount + sessionStats.reviewCount > 0
    }

    private var canStrengthen: Bool {
        SessionBuilder.canStrengthen(records: srsRecords, activeIds: Set(activeGrammarPoints.map(\.id)))
    }

    /// When the next review falls due, for the "done for today" card.
    private var nextReviewText: String? {
        let activeIds = Set(activeGrammarPoints.map(\.id))
        let now = Date.now
        guard let next = srsRecords
            .filter({ activeIds.contains($0.grammarId) && $0.fsrsDue > now })
            .map(\.fsrsDue)
            .min() else { return nil }
        return next.formatted(.relative(presentation: .named))
    }

    // MARK: - Session Preview

    private var sessionStats: SessionStats {
        guard !grammarPoints.isEmpty else {
            return SessionStats(newCount: 0, reviewCount: 0, totalDue: 0)
        }
        let newCount = todayNewCount
        let grammar = SessionBuilder.previewSession(
            allPoints: grammarPoints,
            context: modelContext,
            newCount: newCount
        )
        guard combinedDrills, !particleExercises.isEmpty else {
            return grammar
        }

        // Mirror the cap applied in `startSession`: particles are limited to
        // ~15% of the combined session and appended in review-then-new order,
        // so the cap consumes particle reviews before particle new items.
        let particle = ParticleSessionBuilder.previewSession(
            allExercises: particleExercises,
            context: modelContext,
            newCount: newCount
        )
        let grammarTotal = grammar.newCount + grammar.reviewCount
        let particleTotal = particle.newCount + particle.reviewCount
        let maxParticleCount = grammarTotal == 0
            ? min(particleTotal, 1)
            : max(1, Int((Double(grammarTotal) * 0.15 / 0.85).rounded()))
        let cappedParticleCount = min(maxParticleCount, particleTotal)
        let cappedParticleReview = min(particle.reviewCount, cappedParticleCount)
        let cappedParticleNew = cappedParticleCount - cappedParticleReview

        return SessionStats(
            newCount: grammar.newCount + cappedParticleNew,
            reviewCount: grammar.reviewCount + cappedParticleReview,
            totalDue: grammar.totalDue + particle.totalDue
        )
    }

    private var lastReviewText: String {
        let interval = UserDefaults.standard.double(forKey: "lastStudyDate")
        guard interval > 0 else { return "Never" }
        let date = Date(timeIntervalSince1970: interval)
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: .now)
        if let days = components.day, days > 0 {
            return "\(days)d ago"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m ago"
        }
        return "Just now"
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 6) {
                    Text("Grammar Drill")
                        .font(.system(size: scaled(34), weight: .heavy))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)

                    Text("by JLPT level")
                        .font(.system(size: scaled(13), weight: .medium))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.top, 12)

                levelPicker
                    .padding(.horizontal)

                if !store.isUnlocked {
                    upgradeBanner
                        .padding(.horizontal)
                }

                // Stats Card
                VStack(spacing: 0) {
                    HStack {
                        Text("Stats")
                            .font(.system(size: scaled(18), weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(activeGrammarPoints.count) total")
                            .font(.system(size: scaled(14)))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    ForEach(MasteryLevel.allCases, id: \.self) { level in
                        HStack(spacing: 10) {
                            Image(systemName: level.icon)
                                .font(.system(size: scaled(14)))
                                .foregroundColor(level.color)
                                .frame(width: 24)
                            Text(level.rawValue)
                                .font(.system(size: scaled(15)))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(masteryCounts[level] ?? 0)")
                                .font(.system(size: scaled(15), weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                    }
                    .padding(.bottom, 10)
                }
                .tactileCard(cornerRadius: 20)
                .padding(.horizontal)

                // Today's Session Card
                VStack(spacing: 0) {
                    HStack {
                        Text("Today's Session")
                            .font(.system(size: scaled(18), weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    if hasWorkToday {
                        todayWorkSummary
                    } else {
                        doneForTodaySummary
                    }

                    HStack {
                        Spacer()
                        Text("Last review: \(lastReviewText)")
                            .font(.system(size: scaled(12)))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
                .tactileCard(cornerRadius: 20)
                .padding(.horizontal)

                // Session Buttons
                if isLoading {
                    ProgressView()
                        .padding()
                }

                sessionButtons
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                // Secondary navigation — Grammar List and Stats live here rather than on the hub.
                HStack(spacing: 10) {
                    NavigationLink(value: HubDestination.grammarList) {
                        Label("Grammar List", systemImage: "book.fill")
                            .font(.system(size: scaled(15), weight: .semibold))
                    }
                    .buttonStyle(TactileSecondaryButtonStyle(foreground: Theme.ink))

                    NavigationLink(value: HubDestination.stats) {
                        Label("Stats", systemImage: "chart.bar.fill")
                            .font(.system(size: scaled(15), weight: .semibold))
                    }
                    .buttonStyle(TactileSecondaryButtonStyle(foreground: Theme.ink))
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .padding(.bottom, 20)
        }
        .background(TactileBackdrop().ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("All caught up!", isPresented: $showAllCaughtUp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Come back tomorrow for your next review.")
        }
        .navigationDestination(isPresented: $navigateToExercise) {
            if let items = sessionItems {
                ExerciseView(
                    sessionItems: items,
                    exercisePool: exercisePool,
                    newPatternIds: newPatternIds,
                    remainingWork: remainingWorkProvider(for: activeKind),
                    buildNextSession: nextSessionBuilder(for: activeKind),
                    replacementNewPattern: { excluding in
                        SessionBuilder.replacementNewPattern(
                            allPoints: grammarPoints,
                            exercisePool: exercisePool,
                            context: modelContext,
                            excluding: excluding
                        )
                    }
                )
            }
        }
        .onAppear {
            loadData()
        }
        .onChange(of: combinedDrills) {
            loadData()
        }
        .onChange(of: store.isUnlocked) {
            loadData()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Today's Session Card

    private var todayWorkSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sessionStats.newCount > 0 {
                HStack(spacing: 4) {
                    Text("\(sessionStats.newCount)")
                        .font(.system(size: scaled(16), weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brand)
                    Text("new")
                        .font(.system(size: scaled(15)))
                        .foregroundStyle(Theme.brand)
                    if newLeftToday > sessionStats.newCount {
                        Text("(\(newLeftToday) left today)")
                            .font(.system(size: scaled(13)))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }

            HStack(spacing: 4) {
                Text("\(sessionStats.reviewCount)")
                    .font(.system(size: scaled(16), weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("review")
                    .font(.system(size: scaled(15)))
                    .foregroundStyle(Theme.ink)
                if sessionStats.totalDue > 0 {
                    Text("(of \(sessionStats.totalDue) due)")
                        .font(.system(size: scaled(13)))
                        .foregroundStyle(Theme.inkMuted)
                }
            }

            if newLeftToday == 0, let reason = dailyPlan?.holdBackReason {
                Text(reason)
                    .font(.system(size: scaled(13)))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var doneForTodaySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Done for today", systemImage: "checkmark.circle.fill")
                .font(.system(size: scaled(16), weight: .semibold))
                .foregroundStyle(Theme.correctBorder)

            if let nextReviewText {
                Text("Next review \(nextReviewText).")
                    .font(.system(size: scaled(13)))
                    .foregroundStyle(Theme.inkMuted)
            }
            if canStrengthen {
                Text("Want more? Strengthen the patterns you're most likely to be forgetting.")
                    .font(.system(size: scaled(13)))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: - Session Buttons

    @ViewBuilder
    private var sessionButtons: some View {
        VStack(spacing: 10) {
            if hasWorkToday {
                Button {
                    startSession(.today)
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Today's Session")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: scaled(18), weight: .bold))
                }
                .buttonStyle(TactilePrimaryButtonStyle())
                .disabled(isLoading)

                if sessionStats.newCount > 0 && sessionStats.reviewCount > 0 {
                    Button {
                        startSession(.reviewOnly)
                    } label: {
                        Text("Review Only")
                            .font(.system(size: scaled(18), weight: .semibold))
                    }
                    .buttonStyle(TactileSecondaryButtonStyle())
                    .disabled(isLoading)
                }
            } else {
                if canStrengthen {
                    Button {
                        startSession(.strengthen)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Strengthen")
                            Image(systemName: "dumbbell.fill")
                        }
                        .font(.system(size: scaled(18), weight: .bold))
                    }
                    .buttonStyle(TactilePrimaryButtonStyle())
                    .disabled(isLoading)
                }

                if unseenCount > 0 {
                    let extra = min(defaultNewCount, unseenCount)
                    Button {
                        startSession(.extraNew)
                    } label: {
                        Text(extra == 1 ? "Learn 1 More Pattern" : "Learn \(extra) More Patterns")
                            .font(.system(size: scaled(18), weight: .semibold))
                    }
                    .buttonStyle(TactileSecondaryButtonStyle())
                    .disabled(isLoading)
                }
            }
        }
    }

    /// Work left after a session of `kind`, for the summary's "Keep Going" prompt.
    private func remainingWorkProvider(for kind: SessionKind) -> (() -> (due: Int, new: Int))? {
        switch kind {
        case .today:
            return { (sessionStats.totalDue, newLeftToday) }
        case .reviewOnly, .extraNew:
            return { (sessionStats.totalDue, 0) }
        case .strengthen:
            return nil
        }
    }

    /// Builds the session "Keep Going" continues with after a session of `kind`.
    private func nextSessionBuilder(for kind: SessionKind) -> (() -> (items: [SessionExercise], newPatternIds: Set<String>))? {
        switch kind {
        case .today:
            return { buildSessionItems(newCount: todayNewCount) }
        case .reviewOnly, .extraNew:
            return { buildSessionItems(newCount: 0) }
        case .strengthen:
            return nil
        }
    }

    private var levelPicker: some View {
        TactileLevelPicker(levels: Self.allLevels, selected: enabledLevelsSet, showsDot: true, onToggle: toggleLevel)
    }

    private var upgradeBanner: some View {
        UpgradeBanner(subtitle: "Free: 20 patterns per level + all particles", price: store.displayPrice) {
            showPaywall = true
        }
    }

    private func loadData() {
        grammarPoints = Entitlement.filterFreeGrammar(GrammarLoader.loadAll())
        var pool = Entitlement.filterFreeExercisePool(GrammarLoader.buildExercisePool())
        particleExercises = combinedDrills ? ParticleLoader.loadAll() : []
        if combinedDrills {
            let particlePool = ParticleLoader.buildExercisePool()
            pool.merge(particlePool) { _, new in new }
        }
        exercisePool = pool
    }

    private func startSession(_ kind: SessionKind) {
        isLoading = true
        Task {
            let built: (items: [SessionExercise], newPatternIds: Set<String>)
            switch kind {
            case .today:
                built = buildSessionItems(newCount: todayNewCount)
            case .reviewOnly:
                built = buildSessionItems(newCount: 0)
            case .extraNew:
                built = buildSessionItems(newCount: defaultNewCount)
            case .strengthen:
                let items = SessionBuilder.buildStrengthenSession(
                    allPoints: grammarPoints,
                    exercisePool: exercisePool,
                    context: modelContext
                )
                built = (items, [])
            }

            await MainActor.run {
                isLoading = false
                if built.items.isEmpty {
                    showAllCaughtUp = true
                } else {
                    activeKind = kind
                    sessionItems = built.items
                    newPatternIds = built.newPatternIds
                    navigateToExercise = true
                }
            }
        }
    }

    /// Build the grammar session (plus particles in combined mode). Shared by the Home
    /// buttons and ExerciseView's in-place "Keep Going" action.
    private func buildSessionItems(newCount: Int) -> (items: [SessionExercise], newPatternIds: Set<String>) {
        let built = SessionBuilder.buildSession(
            allPoints: grammarPoints,
            exercisePool: exercisePool,
            context: modelContext,
            newCount: newCount
        )
        var items = built.items

        // Mix in particle exercises when combined mode is on.
        // Cap particles at ~15% of the final session so they stay an occasional flavor.
        // The cap is passed *into* the builder so it doesn't insert SRS rows for items
        // that would be dropped — otherwise undrilled particles accumulate as phantom due cards.
        if combinedDrills {
            let grammarCount = items.count
            let maxParticleCount = grammarCount == 0
                ? 1
                : max(1, Int((Double(grammarCount) * 0.15 / 0.85).rounded()))
            let particleItems = ParticleSessionBuilder.buildSession(
                allExercises: particleExercises,
                context: modelContext,
                newCount: newCount,
                maxItems: maxParticleCount
            )
            // Scatter particles at random positions rather than shuffling the whole
            // session, which would undo SessionBuilder's new-pattern spacing.
            for particle in particleItems {
                items.insert(particle, at: Int.random(in: 0...items.count))
            }
        }

        return (items, built.newPatternIds)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(for: [SRSRecord.self, StudyLog.self], inMemory: true)
    .environment(StoreManager())
}
