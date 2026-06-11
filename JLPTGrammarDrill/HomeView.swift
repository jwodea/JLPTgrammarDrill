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
    @State private var isLoading = false
    @State private var showAllCaughtUp = false
    @State private var navigateToExercise = false


    private var streakCount: Int {
        UserDefaults.standard.integer(forKey: "streakCount")
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

    private var activeGrammarPoints: [GrammarPoint] {
        let levels = Set(enabledLevelsString.split(separator: ",").map(String.init))
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
                        .font(.system(size: scaled(36), weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    HStack(spacing: 6) {
                        Text("J L P T")
                            .font(.system(size: scaled(12), weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.secondary)
                        
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 1, height: 12)

                        Text("Grammar Mastery")
                            .font(.system(size: scaled(12), weight: .medium))
                            .foregroundColor(.secondary)

                        if streakCount > 0 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(width: 1, height: 12)
                            Label("\(streakCount)d", systemImage: "flame.fill")
                                .font(.system(size: scaled(12), weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.top, 12)

                if !store.isUnlocked {
                    upgradeBanner
                        .padding(.horizontal)
                }

                // Stats Card
                VStack(spacing: 0) {
                    HStack {
                        Text("Stats")
                            .font(.system(size: scaled(18), weight: .semibold))
                        Spacer()
                        Text("\(activeGrammarPoints.count) total")
                            .font(.system(size: scaled(14)))
                            .foregroundColor(.secondary)
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
                            Spacer()
                            Text("\(masteryCounts[level] ?? 0)")
                                .font(.system(size: scaled(15), weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                    }
                    .padding(.bottom, 10)
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Today's Session Card
                VStack(spacing: 0) {
                    HStack {
                        Text("Today's Session")
                            .font(.system(size: scaled(18), weight: .semibold))
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
                                    .foregroundColor(.accentColor)
                                Text("new")
                                    .font(.system(size: scaled(15)))
                                    .foregroundColor(.accentColor)
                            }
                        }

                        HStack(spacing: 4) {
                            Text("\(sessionStats.reviewCount)")
                                .font(.system(size: scaled(16), weight: .bold))
                                .foregroundColor(.secondary)
                            Text("review")
                                .font(.system(size: scaled(15)))
                                .foregroundColor(.secondary)
                            if sessionStats.totalDue > 0 {
                                Text("(of \(sessionStats.totalDue) due)")
                                    .font(.system(size: scaled(13)))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    HStack {
                        Spacer()
                        Text("Last review: \(lastReviewText)")
                            .font(.system(size: scaled(12)))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
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
                        Text("New and Review")
                            .font(.system(size: scaled(18), weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(isLoading)

                    Button {
                        startSession(newCount: 0)
                    } label: {
                        Text("Review Only")
                            .font(.system(size: scaled(18), weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.accentColor)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                            )
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("Grammar Drill")
        .navigationBarTitleDisplayMode(.inline)
        .alert("All caught up!", isPresented: $showAllCaughtUp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Come back tomorrow for your next review.")
        }
        .navigationDestination(isPresented: $navigateToExercise) {
            if let items = sessionItems {
                ExerciseView(sessionItems: items, exercisePool: exercisePool)
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

    private var upgradeBanner: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: scaled(16), weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(colors: [.accentColor, .purple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock the full version")
                        .font(.system(size: scaled(15), weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Free: 20 patterns per level + all particles")
                        .font(.system(size: scaled(12)))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let price = store.displayPrice {
                    Text(price)
                        .font(.system(size: scaled(15), weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: scaled(12), weight: .semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
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
            var items = SessionBuilder.buildSession(
                allPoints: grammarPoints,
                exercisePool: exercisePool,
                context: modelContext,
                newCount: newCount
            )

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
                items.append(contentsOf: particleItems)
                items.shuffle()
            }

            await MainActor.run {
                isLoading = false
                if items.isEmpty {
                    showAllCaughtUp = true
                } else {
                    sessionItems = items
                    navigateToExercise = true
                }
            }
        }
    }
}
