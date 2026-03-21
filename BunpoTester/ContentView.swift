import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SRSRecord.self, inMemory: true)
}
