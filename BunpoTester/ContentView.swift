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
                    Text("Today")
                }

                NavigationStack {
                    GrammarBrowserView()
                }
                .tabItem {
                    Image(systemName: "book.fill")
                    Text("Grammar")
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
            Text("文法テスター")
                .font(.system(size: 28, weight: .bold))
            Text("BunpoTester")
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
