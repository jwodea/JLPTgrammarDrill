import SwiftUI
import SwiftData

struct ParticleHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var srsRecords: [SRSRecord]
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale
    @AppStorage(ParticleSessionBuilder.defaultNewCountKey) private var defaultNewCount = ParticleSessionBuilder.defaultNewCount
    @AppStorage(SettingsView.combinedDrillsKey) private var combinedDrills = false

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

    private var masteryCounts: [MasteryLevel: Int] {
        var counts: [MasteryLevel: Int] = [:]
        for level in MasteryLevel.allCases {
            counts[level] = 0
        }

        let particleIds = Set(particleExercises.map(\.id))
        let particleRecords = srsRecords.filter { particleIds.contains($0.grammarId) }
        let seenIds = Set(particleRecords.map(\.grammarId))
        counts[.new] = particleExercises.count - seenIds.count

        for record in particleRecords {
            let level = MasteryLevel.level(for: record)
            counts[level, default: 0] += 1
        }

        return counts
    }

    // MARK: - Session Preview

    private var sessionStats: ParticleSessionStats {
        guard !particleExercises.isEmpty else {
            return ParticleSessionStats(newCount: 0, reviewCount: 0, totalDue: 0)
        }
        return ParticleSessionBuilder.previewSession(
            allExercises: particleExercises,
            context: modelContext,
            newCount: defaultNewCount
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
                // Combined mode notice
                if combinedDrills {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: scaled(13)))
                        Text("Particles are also mixed into 文法 sessions")
                            .font(.system(size: scaled(13)))
                    }
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                // Header
                VStack(spacing: 4) {
                    Text("助詞ドリル")
                        .font(.system(size: scaled(30), weight: .bold))
                    HStack(spacing: 8) {
                        Text("Particle Drill")
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
                        Text("\(particleExercises.count) total")
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
            particleExercises = ParticleLoader.loadAll()
            exercisePool = ParticleLoader.buildExercisePool()
        }
    }

    private func startSession(newCount: Int) {
        isLoading = true
        Task {
            let items = ParticleSessionBuilder.buildSession(
                allExercises: particleExercises,
                context: modelContext,
                newCount: newCount
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
