import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isReady = false
    @State private var showSettings = false

    var body: some View {
        if isReady {
            NavigationStack {
                HubView(showSettings: $showSettings)
                    .navigationDestination(for: HubDestination.self) { destination in
                        switch destination {
                        case .grammarDrill:
                            HomeView()
                        case .otherDrills:
                            OtherDrillsView()
                        case .particlePractice:
                            ParticlePracticeView()
                        case .audioDrill:
                            AudioDrillHomeView()
                        case .grammarList:
                            GrammarBrowserView()
                        case .stats:
                            StatsView(kind: .grammar)
                        }
                    }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        } else {
            SplashView()
                .task {
                    isReady = true
                }
        }
    }
}

// MARK: - Hub Navigation

enum HubDestination: Hashable {
    case grammarDrill
    case otherDrills
    case particlePractice
    case audioDrill
    case grammarList
    case stats
}

// MARK: - Hub View

struct HubView: View {
    @Binding var showSettings: Bool
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 2) {
                        Text("JLPT")
                            .font(.system(size: scaled(14), weight: .bold, design: .monospaced))
                            .tracking(6)
                            .foregroundStyle(.secondary)

                        Text("Grammar Drill")
                            .font(.system(size: scaled(34), weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 8)

                    // Navigation Cards — glass layer floating over the gradient backdrop
                    GlassEffectContainer(spacing: 14) {
                        VStack(spacing: 14) {
                            NavigationLink(value: HubDestination.grammarDrill) {
                                HubCard(icon: "play.fill", title: "Drill Now", color: .blue, fontScale: fontScale)
                            }

                            NavigationLink(value: HubDestination.otherDrills) {
                                HubCard(icon: "square.grid.2x2.fill", title: "Other Drills", color: .orange, fontScale: fontScale)
                            }

                            Button {
                                showSettings = true
                            } label: {
                                HubCard(icon: "gearshape", title: "Settings", color: .gray, fontScale: fontScale)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
                .frame(minHeight: geo.size.height)
                .frame(maxWidth: .infinity)
            }
        }
        .background(GlassBackdrop().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Other Drills

/// Secondary drill modes, kept off the hub so the main screen stays simple.
struct OtherDrillsView: View {
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 14) {
                    NavigationLink(value: HubDestination.particlePractice) {
                        HubCard(icon: "character.ja", title: "Particle Practice", color: .orange, fontScale: fontScale)
                    }

                    NavigationLink(value: HubDestination.audioDrill) {
                        HubCard(icon: "mic.fill", title: "Audio Drill", color: .pink, fontScale: fontScale)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(GlassBackdrop().ignoresSafeArea())
        .navigationTitle("Other Drills")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Hub Card

private struct HubCard: View {
    let icon: String
    let title: String
    let color: Color
    let fontScale: Double

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: scaled(22), weight: .medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)

            Text(title)
                .font(.system(size: scaled(18), weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: scaled(14), weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
    }
}

// MARK: - Splash

struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "character.book.closed.fill.ja")
                .font(.system(size: 64))
                .foregroundStyle(.accent)
            Text("JLPT Grammar Drill")
                .font(.system(size: 28, weight: .bold))
            ProgressView("Loading data…")
                .padding(.top, 8)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [SRSRecord.self, StudyLog.self, AudioCard.self, AudioAttempt.self], inMemory: true)
        .environment(StoreManager())
}
