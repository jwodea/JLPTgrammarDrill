import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var srsRecords: [SRSRecord]
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale
    @AppStorage(SessionBuilder.newPerSessionKey) private var newPerSession = SessionBuilder.defaultNewPerSession

    @State private var grammarPoints: [GrammarPoint] = []
    @State private var exercisePool: [String: [SessionExercise]] = [:]
    @State private var sessionItems: [SessionExercise]?
    @State private var isLoading = false
    @State private var showAllCaughtUp = false
    @State private var navigateToExercise = false
    @State private var showSettings = false

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

    private var masteryCounts: [MasteryLevel: Int] {
        var counts: [MasteryLevel: Int] = [:]
        for level in MasteryLevel.allCases {
            counts[level] = 0
        }

        let seenIds = Set(srsRecords.map(\.grammarId))
        counts[.new] = grammarPoints.count - seenIds.count

        for record in srsRecords {
            let level = MasteryLevel.level(for: record)
            counts[level, default: 0] += 1
        }

        return counts
    }

    // MARK: - Session Preview

    private var sessionStats: SessionStats {
        guard !grammarPoints.isEmpty else {
            return SessionStats(newCount: 0, reviewCount: 0, totalDue: 0, canUnlockNew: true)
        }
        return SessionBuilder.previewSession(
            allPoints: grammarPoints,
            context: modelContext,
            includeNew: true,
            newPerSession: newPerSession
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
                VStack(spacing: 4) {
                    Text("文法テスター")
                        .font(.system(size: scaled(30), weight: .bold))
                    HStack(spacing: 8) {
                        Text("BunpoTester")
                            .font(.system(size: scaled(15)))
                            .foregroundColor(.secondary)
                        if streakCount > 0 {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text("\(streakCount) day streak")
                                .font(.system(size: scaled(15), weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.top, 12)

                // Stats Card
                VStack(spacing: 0) {
                    HStack {
                        Text("Stats")
                            .font(.system(size: scaled(18), weight: .semibold))
                        Spacer()
                        Text("\(grammarPoints.count) total")
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
                        if sessionStats.canUnlockNew && sessionStats.newCount > 0 {
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

                        if !sessionStats.canUnlockNew {
                            Text("Master current patterns to unlock new ones")
                                .font(.system(size: scaled(12)))
                                .foregroundColor(.orange)
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
                    if sessionStats.canUnlockNew && sessionStats.newCount > 0 {
                        Button {
                            startSession(includeNew: true)
                        } label: {
                            Text("Start")
                                .font(.system(size: scaled(18), weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(isLoading)
                    }

                    Button {
                        startSession(includeNew: false)
                    } label: {
                        let isOnlyButton = !sessionStats.canUnlockNew || sessionStats.newCount == 0
                        Text(isOnlyButton ? "Start" : "Review Only")
                            .font(.system(size: scaled(18), weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isOnlyButton ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundColor(isOnlyButton ? .white : .accentColor)
                            .cornerRadius(12)
                            .overlay(
                                isOnlyButton ? nil :
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
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
            grammarPoints = GrammarLoader.loadAll()
            exercisePool = GrammarLoader.buildExercisePool()
        }
    }

    private func startSession(includeNew: Bool) {
        isLoading = true
        Task {
            let items = SessionBuilder.buildSession(
                allPoints: grammarPoints,
                exercisePool: exercisePool,
                context: modelContext,
                includeNew: includeNew,
                newPerSession: newPerSession
            )
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
