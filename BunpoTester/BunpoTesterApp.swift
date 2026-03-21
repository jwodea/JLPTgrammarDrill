import SwiftUI
import SwiftData
import SwiftFSRS

/// Creates a ShortTermScheduler instance.
/// Workaround for the library's internal init — since ShortTermScheduler
/// has no stored properties, we can safely create one via unsafeBitCast from Void.
nonisolated private let seedScheduler: ShortTermScheduler = unsafeBitCast((), to: ShortTermScheduler.self)

@main
struct BunpoTesterApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: SRSRecord.self)
        } catch {
            // Schema mismatch from algorithm change — destroy and recreate
            print("SwiftData migration failed, recreating store: \(error)")
            let config = ModelConfiguration()
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            do {
                modelContainer = try ModelContainer(for: SRSRecord.self)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }

        // TODO: Remove after first run — one-off test seed
        seedTestData()
    }

    private func seedTestData() {
        let context = ModelContext(modelContainer)

        // Clear existing records so we can re-seed
        let existing = (try? context.fetch(FetchDescriptor<SRSRecord>())) ?? []
        for record in existing { context.delete(record) }
        try? context.save()

        let allPoints = GrammarLoader.loadAll()
        let n3Points = allPoints.filter { $0.level == "N3" }.shuffled()
        let toSeed = Array(n3Points.prefix(30))

        for (index, point) in toSeed.enumerated() {
            let record = SRSRecord(grammarId: point.id)

            // Simulate review history to create varied FSRS states
            var card = record.fsrsCard
            let now = Date()

            switch index % 3 {
            case 0:
                // Learning: 2–3 good reviews, last reviewed 2–4 days ago
                let reviewCount = Int.random(in: 2...3)
                var reviewDate = now.addingTimeInterval(-Double.random(in: 2...4) * 86400)
                for i in 0..<reviewCount {
                    let review = seedScheduler.schedule(
                        card: card,
                        algorithm: FSRSAlgorithm.v5,
                        reviewRating: Rating.good,
                        reviewTime: reviewDate
                    )
                    card = review.postReviewCard
                    reviewDate = reviewDate.addingTimeInterval(Double(i + 1) * 86400 * 0.5)
                }
            case 1:
                // Familiar: 5–7 good reviews spread over weeks
                let reviewCount = Int.random(in: 5...7)
                var reviewDate = now.addingTimeInterval(-Double.random(in: 20...30) * 86400)
                for _ in 0..<reviewCount {
                    let review = seedScheduler.schedule(
                        card: card,
                        algorithm: FSRSAlgorithm.v5,
                        reviewRating: Rating.good,
                        reviewTime: reviewDate
                    )
                    card = review.postReviewCard
                    reviewDate = min(now, reviewDate.addingTimeInterval(Double.random(in: 2...5) * 86400))
                }
            default:
                // Confident: 8–12 good reviews spread over months
                let reviewCount = Int.random(in: 8...12)
                var reviewDate = now.addingTimeInterval(-Double.random(in: 50...70) * 86400)
                for _ in 0..<reviewCount {
                    let review = seedScheduler.schedule(
                        card: card,
                        algorithm: FSRSAlgorithm.v5,
                        reviewRating: Rating.good,
                        reviewTime: reviewDate
                    )
                    card = review.postReviewCard
                    reviewDate = min(now, reviewDate.addingTimeInterval(Double.random(in: 3...8) * 86400))
                }
            }

            record.update(from: card)
            // Make them overdue by pushing the due date into the past
            record.fsrsDue = now.addingTimeInterval(-Double.random(in: 0.5...3) * 86400)
            context.insert(record)
        }
        try? context.save()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.accentColor)
        }
        .modelContainer(modelContainer)
    }
}
