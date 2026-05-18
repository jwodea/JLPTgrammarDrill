import Foundation
import SwiftData

@Model
final class StudyLog {
    @Attribute(.unique) var dateKey: String
    var itemsStudied: Int
    var correctCount: Int

    init(dateKey: String, itemsStudied: Int = 0, correctCount: Int = 0) {
        self.dateKey = dateKey
        self.itemsStudied = itemsStudied
        self.correctCount = correctCount
    }

    var accuracy: Double {
        itemsStudied > 0 ? Double(correctCount) / Double(itemsStudied) : 0
    }

    static func record(correct: Bool, context: ModelContext) {
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
        try? context.save()
    }

    static func todayKey() -> String {
        key(for: Date())
    }

    /// Format a date into the canonical `yyyy-MM-dd` study-log key. Used as the
    /// day-boundary primitive for streaks and activity charts, so it must be
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
