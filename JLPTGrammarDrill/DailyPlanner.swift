import Foundation
import SwiftData

/// Today's new-pattern allowance, decided by the app rather than the learner.
struct DailyPlan {
    /// New patterns the planner allotted for the whole day.
    let newAllowance: Int
    /// New patterns already introduced today (counted against the allowance).
    let introducedToday: Int
    /// Why new patterns are being held back, if they are.
    let holdBackReason: String?

    var newRemaining: Int { max(0, newAllowance - introducedToday) }
}

/// Paces the introduction of new grammar patterns.
///
/// Once per day the planner looks at the review workload already scheduled and
/// at recent accuracy, and decides how many new patterns fit:
/// - **Workload:** new patterns fill whatever room the day's reviews leave under
///   the learner's daily goal. The next few days' forecast counts too, so a
///   quiet day just before a heavy one doesn't pile on more.
/// - **Accuracy:** when recent first-try accuracy slips, fewer (or no) new
///   patterns are introduced until it recovers.
/// - **Learning pool:** patterns still in (re)learning are unstable; too many of
///   them at once means consolidating before adding more.
///
/// The allowance is cached for the day so finishing reviews doesn't free up room
/// and keep unlocking more new patterns as the day goes on.
enum DailyPlanner {
    static let dailyGoalKey = "dailyGoalPatterns"
    static let defaultDailyGoal = 20

    /// A new pattern costs more than a review: three intro sentences today, plus
    /// the extra reviews it generates over the following week.
    private static let newPatternCost = 2.0
    private static let maxNewPerDay = 10
    /// Days ahead (after today) averaged into the workload forecast.
    private static let forecastDays = 5
    private static let learningPoolCap = 15

    /// Accuracy guard: look at the last few study days once there's enough data.
    private static let accuracyLookbackDays = 3
    private static let accuracyMinItems = 20
    private static let pauseBelowAccuracy = 0.70
    private static let slowBelowAccuracy = 0.80

    // UserDefaults keys for the cached plan and today's intro counter.
    private static let planDateKey = "dailyPlan.date"
    private static let planAllowanceKey = "dailyPlan.allowance"
    private static let planGoalKey = "dailyPlan.goal"
    private static let planReasonKey = "dailyPlan.reason"
    private static let introducedDateKey = "dailyPlan.introducedDate"
    private static let introducedCountKey = "dailyPlan.introducedCount"

    static var dailyGoal: Int {
        let stored = UserDefaults.standard.integer(forKey: dailyGoalKey)
        return stored > 0 ? stored : defaultDailyGoal
    }

    /// Today's plan, computing and caching the allowance on the first call of the day.
    static func plan(
        records: [SRSRecord],
        activeIds: Set<String>,
        context: ModelContext,
        now: Date = Date()
    ) -> DailyPlan {
        let defaults = UserDefaults.standard
        let today = StudyLog.key(for: now)
        let goal = dailyGoal

        let allowance: Int
        let reason: String?
        if defaults.string(forKey: planDateKey) == today,
           defaults.integer(forKey: planGoalKey) == goal {
            allowance = defaults.integer(forKey: planAllowanceKey)
            reason = defaults.string(forKey: planReasonKey)
        } else {
            (allowance, reason) = computeAllowance(
                records: records, activeIds: activeIds, goal: goal, context: context, now: now
            )
            defaults.set(today, forKey: planDateKey)
            defaults.set(goal, forKey: planGoalKey)
            defaults.set(allowance, forKey: planAllowanceKey)
            defaults.set(reason, forKey: planReasonKey)
        }

        return DailyPlan(
            newAllowance: allowance,
            introducedToday: introducedTodayCount(now: now),
            holdBackReason: reason
        )
    }

    /// Record that a pattern was studied for the first time. Called by
    /// `ExerciseView` when it creates the pattern's SRS record.
    static func recordIntroduction(now: Date = Date()) {
        let defaults = UserDefaults.standard
        let today = StudyLog.key(for: now)
        let count = introducedTodayCount(now: now)
        defaults.set(today, forKey: introducedDateKey)
        defaults.set(count + 1, forKey: introducedCountKey)
    }

    static func introducedTodayCount(now: Date = Date()) -> Int {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: introducedDateKey) == StudyLog.key(for: now) else { return 0 }
        return defaults.integer(forKey: introducedCountKey)
    }

    // MARK: - Allowance

    private static func computeAllowance(
        records: [SRSRecord],
        activeIds: Set<String>,
        goal: Int,
        context: ModelContext,
        now: Date
    ) -> (Int, String?) {
        let active = records.filter { activeIds.contains($0.grammarId) }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        // Workload: everything due by the end of today, and the average daily
        // load over the next few days.
        func endOfDay(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset + 1, to: startOfToday) ?? now
        }
        let dueToday = active.filter { $0.fsrsDue < endOfDay(0) }.count
        let upcoming = active.filter { $0.fsrsDue >= endOfDay(0) && $0.fsrsDue < endOfDay(forecastDays) }.count
        let forecastAverage = Double(upcoming) / Double(forecastDays)
        let projectedLoad = max(Double(dueToday), forecastAverage)

        let room = Double(goal) - projectedLoad
        var allowance = min(maxNewPerDay, max(0, Int((room / newPatternCost).rounded(.down))))
        var reason: String? = allowance == 0 ? "Plenty of reviews today, so no new patterns." : nil

        // Learning pool: don't pile on while many patterns are still unstable.
        let learningCount = active.filter { $0.fsrsStatusRaw == 1 || $0.fsrsStatusRaw == 3 }.count
        let poolRoom = max(0, learningPoolCap - learningCount)
        if poolRoom < allowance {
            allowance = poolRoom
            reason = "Consolidating patterns you're still learning."
        }

        // Accuracy: slow down, then pause, when recent results slip.
        if let accuracy = recentAccuracy(context: context, now: now) {
            if accuracy < pauseBelowAccuracy {
                allowance = 0
                reason = "New patterns paused until accuracy recovers."
            } else if accuracy < slowBelowAccuracy, allowance > 1 {
                allowance /= 2
                reason = "Fewer new patterns while accuracy recovers."
            }
        }

        return (allowance, reason)
    }

    /// Answer accuracy over the last few study days (excluding today, so
    /// the plan is based on settled results), or nil with too little data.
    private static func recentAccuracy(context: ModelContext, now: Date) -> Double? {
        let today = StudyLog.key(for: now)
        let descriptor = FetchDescriptor<StudyLog>(
            predicate: #Predicate { $0.dateKey < today },
            sortBy: [SortDescriptor(\.dateKey, order: .reverse)]
        )
        guard let logs = try? context.fetch(descriptor) else { return nil }
        let recent = logs.prefix(accuracyLookbackDays)
        let items = recent.reduce(0) { $0 + $1.itemsStudied }
        guard items >= accuracyMinItems else { return nil }
        let correct = recent.reduce(0) { $0 + $1.correctCount }
        return Double(correct) / Double(items)
    }
}
