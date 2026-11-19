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

    // MARK: - Session Preview

    private var sessionStats: SessionStats {
        guard !grammarPoints.isEmpty else {
            return SessionStats(newCount: 0, reviewCount: 0, totalDue: 0)
        }
        let grammar = SessionBuilder.previewSession(
            allPoints: grammarPoints,
            context: modelContext,
            newCount: defaultNewCount
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
            newCount: defaultNewCount
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
                    }
                    .padding(.horizontal, 16)

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

                VStack(spacing: 10) {
                    Button {
                        startSession(newCount: defaultNewCount)
                    } label: {
                        HStack(spacing: 8) {
                            Text("New and Review")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: scaled(18), weight: .bold))
                    }
                    .buttonStyle(TactilePrimaryButtonStyle())
                    .disabled(isLoading)

                    Button {
                        startSession(newCount: 0)
                    } label: {
                        Text("Review Only")
                            .font(.system(size: scaled(18), weight: .semibold))
                    }
                    .buttonStyle(TactileSecondaryButtonStyle())
                    .disabled(isLoading)
                }
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
                    remainingDueCount: { sessionStats.totalDue },
                    buildReviewSession: {
                        let built = buildSessionItems(newCount: 0)
                        return built.items
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

    private func startSession(newCount: Int) {
        isLoading = true
        Task {
            let built = buildSessionItems(newCount: newCount)

            await MainActor.run {
                isLoading = false
                if built.items.isEmpty {
                    showAllCaughtUp = true
                } else {
                    sessionItems = built.items
                    newPatternIds = built.newPatternIds
                    navigateToExercise = true
                }
            }
        }
    }

    /// Build the grammar session (plus particles in combined mode). Shared by the Home
    /// buttons and ExerciseView's in-place "Keep Reviewing" action.
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
