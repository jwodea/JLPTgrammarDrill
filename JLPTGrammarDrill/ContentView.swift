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
                VStack(spacing: 40) {
                    // Header
                    VStack(spacing: 10) {
                        VStack(spacing: 6) {
                            VStack(spacing: 0) {
                                Text("JLPT")
                                Text("Grammar Drill")
                            }
                            .font(.system(size: scaled(34), weight: .heavy))
                            .tracking(-0.8)
                            .foregroundStyle(Theme.ink)

                            Text("Daily grammar & particle practice")
                                .font(.system(size: scaled(15), weight: .medium))
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }

                    // Navigation Cards
                    VStack(spacing: 14) {
                        NavigationLink(value: HubDestination.grammarDrill) {
                            HubCard(icon: "play.fill", title: "Drill Now",
                                    subtitle: "Today's grammar session",
                                    style: .brand, fontScale: fontScale)
                        }

                        NavigationLink(value: HubDestination.otherDrills) {
                            HubCard(icon: "square.grid.2x2.fill", title: "Other Drills",
                                    subtitle: "Particle Practice & Audio Drill",
                                    style: .amber, fontScale: fontScale)
                        }

                        Button {
                            showSettings = true
                        } label: {
                            HubCard(icon: "gearshape", title: "Settings",
                                    subtitle: "Study, voice & display",
                                    style: .neutral, fontScale: fontScale)
                        }
                    }
                    .buttonStyle(TactileCardButtonStyle())
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)
                .frame(minHeight: geo.size.height)
                .frame(maxWidth: .infinity)
            }
        }
        .background(TactileBackdrop().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Other Drills

/// Secondary drill modes, kept off the hub so the main screen stays simple.
struct OtherDrillsView: View {
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NavigationLink(value: HubDestination.particlePractice) {
                    HubCard(glyph: "は", title: "Particle Practice",
                            style: .amber, fontScale: fontScale)
                }

                NavigationLink(value: HubDestination.audioDrill) {
                    HubCard(icon: "mic.fill", title: "Audio Drill",
                            style: .brand, fontScale: fontScale)
                }
            }
            .buttonStyle(TactileCardButtonStyle())
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(TactileBackdrop().ignoresSafeArea())
        .navigationTitle("Other Drills")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Hub Card

/// Row content for a hub card. The card surface itself comes from
/// `TactileCardButtonStyle` on the enclosing button.
private struct HubCard: View {
    enum Style {
        case brand, amber, neutral

        var foreground: Color {
            switch self {
            case .brand: Theme.brand
            case .amber: Theme.amber
            case .neutral: Theme.inkMuted
            }
        }

        var tint: Color {
            switch self {
            case .brand: Theme.brandTint
            case .amber: Theme.amberTint
            case .neutral: Theme.slateTint
            }
        }

        var border: Color {
            switch self {
            case .brand: Theme.brandBorder
            case .amber: Theme.amberBorder
            case .neutral: Theme.hairline
            }
        }
    }

    var icon: String = ""
    /// Text shown in place of the SF Symbol when no suitable symbol exists.
    var glyph: String? = nil
    let title: String
    var subtitle: String? = nil
    let style: Style
    let fontScale: Double

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let glyph {
                    Text(glyph)
                } else {
                    Image(systemName: icon)
                }
            }
            .font(.system(size: scaled(20), weight: .medium))
            .foregroundStyle(style.foreground)
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style.tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style.border, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: scaled(17), weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: scaled(13), weight: .medium))
                        .foregroundStyle(Theme.inkMuted)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: scaled(14), weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(16)
        .contentShape(Rectangle())
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
