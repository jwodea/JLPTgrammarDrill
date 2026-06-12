import SwiftUI
import SwiftData

/// Landing screen for the audio drill (発話) tab.
struct AudioDrillHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreManager.self) private var store
    @Query private var audioCards: [AudioCard]
    @State private var showPaywall = false

    @AppStorage(AudioDrillSettings.activeLevelsCSVKey)
    private var activeLevelsCSV = AudioDrillSettings.defaultActiveLevelsCSV
    @AppStorage(AudioDrillSettings.dailyNewCardBudgetKey)
    private var dailyNewCardBudget = AudioDrillSettings.defaultDailyNewCardBudget
    @AppStorage(AudioDrillSettings.learningPoolCapKey)
    private var learningPoolCap = AudioDrillSettings.defaultLearningPoolCap

    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    @State private var allExercises: [AudioExercise] = []
    @State private var queue: [AudioQueueItem] = []
    @State private var navigateToDrill = false
    @State private var navigateToHistory = false
    @State private var navigateToBrowser = false
    @State private var navigateToSettings = false
    @State private var showAllCaughtUp = false

    private var activeLevels: Set<String> {
        Set(activeLevelsCSV.split(separator: ",").map(String.init))
    }

    private func toggleLevel(_ level: String) {
        var current = activeLevels
        if current.contains(level) {
            // Don't allow disabling all levels.
            if current.count > 1 {
                current.remove(level)
            }
        } else {
            current.insert(level)
        }
        activeLevelsCSV = AudioDrillSettings.allLevels
            .filter { current.contains($0) }
            .joined(separator: ",")
    }

    private var srs: AudioSRSService {
        AudioSRSService(context: modelContext, allExercises: allExercises)
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                levelPicker.padding(.horizontal)

                if !store.isUnlocked {
                    upgradeBanner.padding(.horizontal)
                }

                if !allExercises.isEmpty {
                    statsCard
                    primaryButtons
                    secondaryButtons
                } else {
                    ProgressView("Loading exercises…")
                        .padding(.top, 40)
                }
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("Audio Drill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    navigateToSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .navigationDestination(isPresented: $navigateToDrill) {
            AudioDrillView(queue: queue, allExercises: allExercises)
        }
        .navigationDestination(isPresented: $navigateToHistory) {
            AudioHistoryView(allExercises: allExercises)
        }
        .navigationDestination(isPresented: $navigateToBrowser) {
            AudioBrowserView()
        }
        .navigationDestination(isPresented: $navigateToSettings) {
            AudioDrillSettingsView()
        }
        .alert("All caught up!", isPresented: $showAllCaughtUp) {
            Button("Drill 5 more") { startExtraDrill(count: 5) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("No new or due audio cards right now. Come back later, raise your daily budget in Settings, or grab 5 more new sentences off-schedule.")
        }
        .onAppear { reload() }
        .onChange(of: activeLevelsCSV) { reload() }
        .onChange(of: dailyNewCardBudget) { reload() }
        .onChange(of: learningPoolCap) { reload() }
        .onChange(of: store.isUnlocked) { reload() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var levelPicker: some View {
        HStack(spacing: 8) {
            ForEach(AudioDrillSettings.allLevels, id: \.self) { level in
                let isOn = activeLevels.contains(level)
                Button {
                    toggleLevel(level)
                } label: {
                    Text(level)
                        .font(.system(size: scaled(14), weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isOn ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(isOn ? .white : .primary)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("JLPT \(level)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
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
                        LinearGradient(colors: [.accentColor, .pink],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock the full version")
                        .font(.system(size: scaled(15), weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Free: 20 sentences per level")
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

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text("Audio Drill")
                .font(.system(size: scaled(36), weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.accentColor, .pink],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Speak the Japanese sentence aloud")
                .font(.system(size: scaled(13)))
                .foregroundColor(.secondary)
        }
        .padding(.top, 12)
    }

    private var statsCard: some View {
        // Reuse the `@Query`'d `audioCards` array for all three counts instead
        // of letting the service re-fetch the table once per stat.
        let service = srs
        let dueCount = service.dueCount(cards: audioCards, activeLevels: activeLevels)
        let learningCount = service.learningPoolCount(cards: audioCards, activeLevels: activeLevels)
        let introduced = service.introducedTodayCount(cards: audioCards)

        return VStack(spacing: 0) {
            HStack {
                Text("Today")
                    .font(.system(size: scaled(18), weight: .semibold))
                Spacer()
                Text(activeLevels.sorted().joined(separator: ", "))
                    .font(.system(size: scaled(13)))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            statRow(icon: "clock.fill", color: .accentColor,
                    label: "Due now", value: "\(dueCount)")
            statRow(icon: "flame.fill", color: .orange,
                    label: "Learning pool", value: "\(learningCount) / \(learningPoolCap)")
            statRow(icon: "sparkles", color: .purple,
                    label: "New today", value: "\(introduced) / \(dailyNewCardBudget)")
                .padding(.bottom, 12)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: scaled(14)))
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .font(.system(size: scaled(15)))
            Spacer()
            Text(value)
                .font(.system(size: scaled(15), weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private var primaryButtons: some View {
        VStack(spacing: 10) {
            Button {
                startDrill()
            } label: {
                Text("Start drill")
                    .font(.system(size: scaled(18), weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Button {
                startExtraDrill(count: 5)
            } label: {
                Label("Drill 5 more new sentences", systemImage: "plus.circle")
                    .font(.system(size: scaled(15), weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(.accentColor)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var secondaryButtons: some View {
        VStack(spacing: 10) {
            Button {
                navigateToHistory = true
            } label: {
                secondaryLabel("Review history", systemImage: "clock.arrow.circlepath")
            }
            Button {
                navigateToBrowser = true
            } label: {
                secondaryLabel("Browse sentences", systemImage: "book")
            }
        }
        .padding(.horizontal)
    }

    private func secondaryLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(title)
                .font(.system(size: scaled(16), weight: .medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: scaled(12), weight: .semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .foregroundColor(.accentColor)
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func reload() {
        allExercises = Entitlement.filterFreeAudio(AudioExerciseLoader.loadAll())
        queue = srs.buildQueue(
            activeLevels: activeLevels,
            dailyNewCardBudget: dailyNewCardBudget,
            learningPoolCap: learningPoolCap
        )
    }

    private func startDrill() {
        let built = srs.buildQueue(
            activeLevels: activeLevels,
            dailyNewCardBudget: dailyNewCardBudget,
            learningPoolCap: learningPoolCap
        )
        queue = built
        if built.isEmpty {
            showAllCaughtUp = true
        } else {
            navigateToDrill = true
        }
    }

    /// Bypass today's budget + learning-pool cap and add `count` new sentences to the queue.
    private func startExtraDrill(count: Int) {
        let extras = srs.extraNewQueue(activeLevels: activeLevels, count: count)
        if extras.isEmpty {
            showAllCaughtUp = true
            return
        }
        queue = extras
        navigateToDrill = true
    }
}
