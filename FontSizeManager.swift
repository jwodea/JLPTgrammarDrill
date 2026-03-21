import SwiftUI

/// Manages a user-adjustable font size scale factor.
/// The scale ranges from 0.8 (smallest) to 1.6 (largest) with 1.0 as default.
struct FontSizeManager {
    static let scaleKey = "fontSizeScale"
    static let defaultScale: Double = 1.0
    static let minScale: Double = 0.8
    static let maxScale: Double = 1.6
    static let step: Double = 0.1

    /// Returns a scaled font size based on the user's preference.
    static func scaled(_ baseSize: CGFloat, scale: Double) -> CGFloat {
        baseSize * CGFloat(scale)
    }
}
