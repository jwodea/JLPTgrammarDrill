import Foundation
import SwiftUI

/// Centralized `@AppStorage`-backed settings for the audio drill tab.
enum AudioDrillSettings {
    static let thresholdKey = "audio.threshold"
    static let stripFinalCopulaKey = "audio.lenientFinalParticles"
    static let dailyNewCardBudgetKey = "audio.dailyNewCardBudget"
    static let learningPoolCapKey = "audio.learningPoolCap"
    static let activeLevelsCSVKey = "audio.activeLevelsCSV"
    static let voiceIdentifierKey = "audio.voiceIdentifier"

    static let defaultThreshold: Double = 0.75
    static let defaultStripFinalCopula = true
    static let defaultDailyNewCardBudget = 5
    static let defaultLearningPoolCap = 15
    static let defaultActiveLevelsCSV = "N5"
    static let defaultVoiceIdentifier = ""  // empty = system default ja-JP voice

    static let allLevels = ["N5", "N4", "N3", "N2", "N1"]

    /// Convenience reader for non-`@AppStorage` callers.
    static var currentActiveLevels: Set<String> {
        let csv = UserDefaults.standard.string(forKey: activeLevelsCSVKey) ?? defaultActiveLevelsCSV
        return Set(csv.split(separator: ",").map(String.init))
    }
}
