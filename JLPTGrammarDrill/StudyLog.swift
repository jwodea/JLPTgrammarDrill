import Foundation
import SwiftData

@Model
final class StudyLog {
    @Attribute(.unique) var dateKey: String
    var itemsStudied: Int
    var correctCount: Int
    /// Active study time for the day. Defaulted so existing stores migrate
    /// lightweight; days logged before this field existed read as 0.
    var secondsStudied: Double = 0

    init(dateKey: String, itemsStudied: Int = 0, correctCount: Int = 0) {
        self.dateKey = dateKey
        self.itemsStudied = itemsStudied
        self.correctCount = correctCount
    }

    var accuracy: Double {
        itemsStudied > 0 ? Double(correctCount) / Double(itemsStudied) : 0
    }

    /// Longest gap between answers still counted as study time. Anything longer
    /// is treated as a break (app backgrounded, walked away) and credited nothing.
    private static let maxCreditedGap: TimeInterval = 120
    /// In-memory only: time of the previous answer in this app launch.
    @MainActor private static var lastRecordDate: Date?

    @MainActor static func record(correct: Bool, context: ModelContext) {
        let now = Date()
        var elapsed: TimeInterval = 0
        if let last = lastRecordDate {
            let gap = now.timeIntervalSince(last)
            if gap > 0 && gap <= maxCreditedGap { elapsed = gap }
        }
        lastRecordDate = now

        let key = Self.todayKey()
        let descriptor = FetchDescriptor<StudyLog>(
            predicate: #Predicate { $0.dateKey == key }
        )
        let log: StudyLog
        if let existing = try? context.fetch(descriptor).first {
            log = existing
        } else {
            log = StudyLog(dateKey: key)
            context.insert(log)
        }
        log.itemsStudied += 1
        if correct { log.correctCount += 1 }
        log.secondsStudied += elapsed
        try? context.save()
    }

    static func todayKey() -> String {
        key(for: Date())
    }

    /// Format a date into the canonical `yyyy-MM-dd` study-log key. Used as the
    /// day-boundary primitive for activity charts, so it must be
    /// stable across device locale and timezone changes — POSIX locale forces a
    /// Gregorian calendar, autoupdating timezone keeps boundaries at the user's
    /// current local midnight even if they cross timezones.
    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    var date: Date {
        Self.formatter.date(from: dateKey) ?? Date()
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
