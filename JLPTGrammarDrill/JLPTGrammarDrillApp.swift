import SwiftUI
import SwiftData
import CoreData

@main
struct JLPTGrammarDrillApp: App {
    let modelContainer: ModelContainer
    @State private var storeManager = StoreManager()

    init() {
        do {
            modelContainer = try ModelContainer(for: SRSRecord.self, StudyLog.self, AudioCard.self, AudioAttempt.self)
        } catch {
            // Destructive recovery only fires on real schema mismatches. Any other
            // init failure (disk full, sandbox issue, corrupted file) surfaces as a
            // crash — silently wiping the user's progress for a transient error is
            // worse than refusing to launch.
            guard Self.isSchemaMismatchError(error) else {
                fatalError("ModelContainer init failed (not a schema mismatch): \(error)")
            }
            print("SwiftData schema mismatch — backing up store before recreating: \(error)")
            Self.backupStoreFiles(at: ModelConfiguration().url)
            do {
                modelContainer = try ModelContainer(for: SRSRecord.self, StudyLog.self, AudioCard.self, AudioAttempt.self)
            } catch {
                fatalError("Failed to create ModelContainer after store reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.accentColor)
                .environment(storeManager)
        }
        .modelContainer(modelContainer)
    }

    /// Match CoreData's migration / schema-mismatch error codes. Checks the
    /// top-level error and any wrapped underlying NSError, since SwiftData
    /// frequently surfaces the CoreData NSError nested in its own type.
    private static func isSchemaMismatchError(_ error: Error) -> Bool {
        let migrationCodes: Set<Int> = [
            NSPersistentStoreIncompatibleVersionHashError,
            NSMigrationError,
            NSMigrationMissingSourceModelError,
            NSMigrationMissingMappingModelError,
            NSInferredMappingModelError,
        ]
        func matches(_ ns: NSError) -> Bool {
            ns.domain == NSCocoaErrorDomain && migrationCodes.contains(ns.code)
        }
        let nsError = error as NSError
        if matches(nsError) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, matches(underlying) {
            return true
        }
        return false
    }

    /// Move the store + its WAL/SHM sidecars into a timestamped Backups folder
    /// next to the store. Moving (rather than removing) preserves the data in
    /// case the user wants to recover, and atomically clears all three files so
    /// the rebuild doesn't accidentally re-attach a stale WAL.
    private static func backupStoreFiles(at storeURL: URL) {
        let fm = FileManager.default
        let backupDir = storeURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = stampFormatter.string(from: Date())

        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = backupDir.appendingPathComponent("\(stamp)-\(src.lastPathComponent)")
            try? fm.moveItem(at: src, to: dst)
        }
    }
}

