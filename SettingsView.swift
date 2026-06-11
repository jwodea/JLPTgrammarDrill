import SwiftUI
import SwiftData

struct SettingsView: View {
    static let enabledLevelsKey = "enabledJLPTLevels"
    static let defaultEnabledLevels = "N5,N4,N3,N2,N1"
    static let combinedDrillsKey = "combinedDrills"
    private static let allLevels = ["N5", "N4", "N3", "N2", "N1"]

    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale
    @AppStorage(SessionBuilder.defaultNewCountKey) private var defaultNewCount = SessionBuilder.defaultNewCount
    @AppStorage(SettingsView.enabledLevelsKey) private var enabledLevelsString = SettingsView.defaultEnabledLevels
    @AppStorage(SettingsView.combinedDrillsKey) private var combinedDrills = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreManager.self) private var store

    @State private var showResetConfirmation = false
    @State private var showPaywall = false

    private var enabledLevelsSet: Set<String> {
        Set(enabledLevelsString.split(separator: ",").map(String.init))
    }

    private func toggleLevel(_ level: String) {
        var current = enabledLevelsSet
        if current.contains(level) {
            // Don't allow disabling all levels
            if current.count > 1 {
                current.remove(level)
            }
        } else {
            current.insert(level)
        }
        enabledLevelsString = Self.allLevels.filter { current.contains($0) }.joined(separator: ",")
    }

    /// Snaps fontScale to the nearest step to avoid floating-point drift.
    private func snapScale() {
        let step = FontSizeManager.step
        fontScale = (fontScale / step).rounded() * step
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.isUnlocked {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Full Version")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            Text("Unlocked")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "lock.open.fill")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unlock Full Version")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Free: 20 patterns and 20 sentences per level + all particles")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if let price = store.displayPrice {
                                    Text(price)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        Button {
                            Task { await store.restore() }
                        } label: {
                            Label("Restore Purchase", systemImage: "arrow.clockwise")
                                .font(.system(size: 15))
                        }
                    }
                } header: {
                    Text("Upgrade")
                }

                #if DEBUG
                Section {
                    Toggle("Simulate Unlocked", isOn: Binding(
                        get: { store.isUnlocked },
                        set: { store.isUnlocked = $0 }
                    ))
                    .font(.system(size: 15))
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug builds only. Flip to test free vs. full-version gating without going through StoreKit.")
                }
                #endif

                Section {
                    NavigationLink {
                        HowItWorksView()
                    } label: {
                        Label("How it works", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("About")
                }

                Section {
                    Stepper(value: $defaultNewCount, in: 1...5) {
                        HStack {
                            Text("Default new patterns")
                                .font(.system(size: 15))
                            Spacer()
                            Text("\(defaultNewCount)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("Combine Grammar and particle drills", isOn: $combinedDrills)
                        .font(.system(size: 15))
                } header: {
                    Text("Study")
                } footer: {
                    if combinedDrills {
                        Text("Grammar and particle exercises will be mixed together in Grammar Drill sessions.")
                    }
                }

                Section {
                    ForEach(Self.allLevels, id: \.self) { level in
                        Toggle(level, isOn: Binding(
                            get: { enabledLevelsSet.contains(level) },
                            set: { _ in toggleLevel(level) }
                        ))
                    }
                } header: {
                    Text("JLPT Levels")
                } footer: {
                    Text("Choose which JLPT levels to include in study sessions.")
                }

                Section {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Font Size")
                                .font(.system(size: 17, weight: .medium))
                            Spacer()
                            Text("\(Int((fontScale * 100).rounded()))%")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button {
                                fontScale = max(FontSizeManager.minScale, fontScale - FontSizeManager.step)
                                snapScale()
                            } label: {
                                Image(systemName: "textformat.size.smaller")
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.borderless)
                            .disabled(fontScale <= FontSizeManager.minScale + 0.01)

                            Slider(
                                value: $fontScale,
                                in: FontSizeManager.minScale...FontSizeManager.maxScale,
                                step: FontSizeManager.step
                            )
                            .onChange(of: fontScale) {
                                snapScale()
                            }

                            Button {
                                fontScale = min(FontSizeManager.maxScale, fontScale + FontSizeManager.step)
                                snapScale()
                            } label: {
                                Image(systemName: "textformat.size.larger")
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.borderless)
                            .disabled(fontScale >= FontSizeManager.maxScale - 0.01)
                        }

                        Button("Reset to Default") {
                            fontScale = FontSizeManager.defaultScale
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Display")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("日本語の文法")
                            .font(.system(size: scaled(26), weight: .bold))

                        Text("Even if it rains, I will go.")
                            .font(.system(size: scaled(17)))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(["ても", "のに", "けど", "から"], id: \.self) { choice in
                                Text(choice)
                                    .font(.system(size: scaled(17)))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Preview")
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Progress")
                            Spacer()
                        }
                    }
                } footer: {
                    Text("This will erase all SRS data, streak, and study history. Grammar patterns will return to \"New\" status.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Reset All Progress?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetProgress()
                }
            } message: {
                Text("This will permanently delete all your SRS records, streak, and study history. This cannot be undone.")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private func resetProgress() {
        // Wipe every SwiftData model that holds progress. StudyLog feeds the
        // streak/activity chart on StatsView; AudioCard + AudioAttempt back
        // the audio drill — if any of these survive, the reset is misleading.
        do {
            try modelContext.delete(model: SRSRecord.self)
            try modelContext.delete(model: StudyLog.self)
            try modelContext.delete(model: AudioCard.self)
            try modelContext.delete(model: AudioAttempt.self)
            try modelContext.save()
        } catch {
            print("Error resetting progress: \(error)")
        }

        // Reset UserDefaults keys
        UserDefaults.standard.removeObject(forKey: "streakCount")
        UserDefaults.standard.removeObject(forKey: "lastStudyDate")
    }
}

// MARK: - How It Works

private struct HowItWorksView: View {
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    private struct Topic: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let body: String
    }

    private let topics: [Topic] = [
        Topic(
            icon: "text.book.closed.fill",
            color: .blue,
            title: "Content",
            body: "Grammar patterns separated into JLPT levels. JLPT does not publish lists of grammar points, so various lists on the internet were used to compile the patterns here. A frontier language model was used to construct about ten examples of each grammar pattern, plus explanations for wrong choices, which were spot-checked by a native speaker."
        ),
        Topic(
            icon: "clock.arrow.circlepath",
            color: .purple,
            title: "How patterns come back",
            body: "Each pattern has its own schedule. Right answers grow the interval; misses shrink it. Five stages reflect interval length:\n• Unseen — not studied yet\n• Learning — under 3 days\n• Familiar — 3 to 14 days\n• Confident — 14 to 60 days\n• Mastered — 60+ days"
        ),
        Topic(
            icon: "rectangle.stack.fill",
            color: .teal,
            title: "Three ways to drill",
            body: "• **Grammar Drill**. Daily fill-in-the-blank session.\n• **Particle Practice**. Endless, weighted toward your weak particles.\n• **Audio Drill**. The goal is to memorize translations of basic sentences to build fluency."
        ),
        Topic(
            icon: "slider.horizontal.3",
            color: .gray,
            title: "What you can adjust",
            body: "**Settings** (gear on home):\n• New patterns per session\n• JLPT levels (N5–N1)\n• Mix particles into Grammar Drill (~15%)\n• Font size\n\n**Audio Settings** (inside Audio Drill):\n• Generosity threshold\n• New sentences per day\n• Voice + preview\n• Ignore final です/ます/だ"
        ),
        Topic(
            icon: "lock.fill",
            color: .green,
            title: "Privacy",
            body: "All progress stays on this device. No accounts, no analytics, no servers."
        ),
 
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Intro
                VStack(alignment: .leading, spacing: 10) {
                    Text("What this app does")
                        .font(.system(size: scaled(20), weight: .bold))
                    Text("Build JLPT grammar knowledge through short daily reviews.")
                        .font(.system(size: scaled(15)))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: topic.icon)
                                .font(.system(size: scaled(18), weight: .semibold))
                                .foregroundColor(topic.color)
                                .frame(width: 28)
                            Text(topic.title)
                                .font(.system(size: scaled(18), weight: .semibold))
                        }
                        Text(.init(topic.body))
                            .font(.system(size: scaled(15)))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if topic.title == "How patterns come back" {
                            NavigationLink {
                                HowReviewsWorkView()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("More on how reviews are scheduled")
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: scaled(12), weight: .semibold))
                                }
                                .font(.system(size: scaled(14), weight: .medium))
                                .foregroundColor(.accentColor)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - How Reviews Are Scheduled

private struct HowReviewsWorkView: View {
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private let sections: [Section] = [
        Section(
            title: "What spaced repetition is",
            body: "When you learn something new, you forget most of it within a day or two. If you review it right before forgetting, the memory lasts longer the next time — and longer again after that. Spaced repetition means timing each review to catch you at the edge of forgetting. Done well, the gap between reviews grows from minutes, to days, to weeks, to months."
        ),
        Section(
            title: "What FSRS does",
            body: "FSRS (Free Spaced Repetition Scheduler) is the part doing the timing. For each card it tracks two things: how strong the memory currently is, and how hard the card is for you personally. After every review it updates both, then picks the next review date so that you have about a 90% chance of remembering when it next comes up."
        ),
        Section(
            title: "How this app uses it",
            body: "In the grammar drill, you see a few example sentences per pattern. Only your first attempt at each sentence counts toward scheduling — retries help you learn the answer, but they don't convince the scheduler you knew it.\n\nIn the particle and audio drills, each item is its own card and is scheduled individually."
        )
    ]

    private struct Tier: Identifiable {
        let id = UUID()
        let name: String
        let range: String
        let color: Color
    }

    // Mirrors StatsView.MasteryColor — keep these in lockstep so the explainer
    // matches the legend the user actually sees on the Stats screen.
    private let tiers: [Tier] = [
        Tier(name: "Learning",  range: "under 3 days",        color: Color(.systemRed)),
        Tier(name: "Familiar",  range: "3 days to 2 weeks",   color: Color(.systemOrange)),
        Tier(name: "Confident", range: "2 weeks to 2 months", color: Color(.systemYellow)),
        Tier(name: "Mastered",  range: "over 2 months",       color: Color(.systemGreen))
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How reviews are scheduled")
                        .font(.system(size: scaled(22), weight: .bold))
                    Text("This app uses an algorithm called FSRS to decide when to show you each grammar point, particle, or audio sentence again. The goal: review things just before you would have forgotten them, so each review strengthens memory instead of just reminding you of something you already know.")
                        .font(.system(size: scaled(15)))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.system(size: scaled(17), weight: .semibold))
                        Text(section.body)
                            .font(.system(size: scaled(15)))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Stats screen groupings")
                        .font(.system(size: scaled(17), weight: .semibold))
                    Text("On the Stats screen, cards are grouped by how far away the next review is:")
                        .font(.system(size: scaled(15)))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tiers) { tier in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(tier.color)
                                    .frame(width: 10, height: 10)
                                Text(tier.name)
                                    .font(.system(size: scaled(15), weight: .medium))
                                Text("— \(tier.range)")
                                    .font(.system(size: scaled(15)))
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 10, height: 10)
                            Text("Unseen")
                                .font(.system(size: scaled(15), weight: .medium))
                            Text("— not studied yet")
                                .font(.system(size: scaled(15)))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    Text("Get a card wrong and it drops back down.")
                        .font(.system(size: scaled(15)))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Review schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}
