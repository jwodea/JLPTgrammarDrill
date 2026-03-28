import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isReady = false

    var body: some View {
        if isReady {
            TabView {
                NavigationStack {
                    HomeView()
                }
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("文法")
                }

                NavigationStack {
                    ParticleHomeView()
                }
                .tabItem {
                    Text("を")
                    Text("助詞")
                }

                NavigationStack {
                    GrammarBrowserView()
                }
                .tabItem {
                    Image(systemName: "book.fill")
                    Text("一覧")
                }
            }
        } else {
            SplashView()
                .task {
                    await seedTestDataAsync(context: modelContext)
                    isReady = true
                }
        }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "character.book.closed.fill.ja")
                .font(.system(size: 64))
                .foregroundStyle(.accent)
            Text("JLPT文法ドリル")
                .font(.system(size: 28, weight: .bold))
            Text("JLPT Grammar Drill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            ProgressView("Loading grammar data…")
                .padding(.top, 8)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SRSRecord.self, inMemory: true)
}
