import SwiftUI

// MARK: - Tactile Study Theme

/// Design tokens for the "Alexandria Tactile Study" redesign: a flat slate
/// canvas, white cards with hairline borders, and a pressable bottom "lip".
/// Every color has a dark-mode variant.
enum Theme {
    // Surfaces
    static let canvas = Color(light: 0xF8FAFC, dark: 0x0B1120)
    static let card = Color(light: 0xFFFFFF, dark: 0x172033)
    static let hairline = Color(light: 0xE2E8F0, dark: 0x2A3650)
    /// The 2pt "lip" under tactile cards and buttons.
    static let lip = Color(light: 0xCBD5E1, dark: 0x050914)

    // Text
    static let ink = Color(light: 0x0F172A, dark: 0xF1F5F9)
    static let inkMuted = Color(light: 0x64748B, dark: 0x94A3B8)

    // Brand blue. `brand` is for text and icons; `brandFill` is a solid
    // button background that keeps white text legible in both modes.
    static let brand = Color(light: 0x094CB2, dark: 0x8AB0F5)
    static let brandFill = Color(light: 0x094CB2, dark: 0x1E5CC8)
    static let brandLip = Color(light: 0x001946, dark: 0x0A2255)
    static let brandTint = Color(light: 0xF0F5FD, dark: 0x16264A)
    static let brandBorder = Color(light: 0xC7D9F5, dark: 0x2A4170)

    // Feedback
    static let correct = Color(light: 0x065F46, dark: 0x6EE7B7)
    static let correctTint = Color(light: 0xECFDF5, dark: 0x0B2E24)
    static let correctBorder = Color(light: 0x059669, dark: 0x10B981)
    static let incorrect = Color(light: 0xBE123C, dark: 0xFDA4AF)
    static let incorrectTint = Color(light: 0xFFF1F2, dark: 0x3A1220)
    static let incorrectBorder = Color(light: 0xFB7185, dark: 0xF43F5E)
    /// Solid rose for filled controls with white content (e.g. the stop-recording button).
    static let incorrectFill = Color(light: 0xE11D48, dark: 0xE11D48)

    // Accents
    static let amber = Color(light: 0xD97706, dark: 0xFBBF24)
    static let amberTint = Color(light: 0xFFFBEB, dark: 0x33260A)
    static let amberBorder = Color(light: 0xFDE68A, dark: 0x5C4410)
    static let slateTint = Color(light: 0xF1F5F9, dark: 0x1E293B)

    // UIKit variants for text drawn by UIKit views (e.g. selectable sentences).
    static let inkUIColor = UIColor(light: 0x0F172A, dark: 0xF1F5F9)
    static let inkMutedUIColor = UIColor(light: 0x64748B, dark: 0x94A3B8)
}

extension Color {
    /// A color that switches between two hex values with the color scheme.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

extension UIColor {
    /// A dynamic color that switches between two hex values with the color scheme.
    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    fileprivate convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Static (non-pressable) tactile card surface: white fill, hairline border, 2pt lip.
    func tactileCard(cornerRadius: CGFloat = 24) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(Theme.card))
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
            .background(shape.fill(Theme.lip).offset(y: 2))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 4)
    }
}

/// Flat slate canvas shared by every screen.
struct TactileBackdrop: View {
    var body: some View {
        Theme.canvas
    }
}

/// White card with a hairline border and a 2pt bottom lip. When pressed it
/// sinks 2pt onto the lip, like a physical key.
struct TactileCardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .background(shape.fill(Theme.card))
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
            .offset(y: pressed ? 2 : 0)
            .background(shape.fill(Theme.lip).offset(y: 2))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 4)
            .animation(.spring(duration: 0.16), value: pressed)
    }
}

/// Solid brand-blue call-to-action button with a darker lip.
/// Full-width by default; pass `fullWidth: false` for inline buttons.
struct TactilePrimaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        TactileButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            cornerRadius: cornerRadius,
            fullWidth: fullWidth,
            foreground: .white,
            fill: Theme.brandFill,
            border: nil,
            lip: Theme.brandLip,
            lipHeight: 3
        )
    }
}

/// White tactile button with brand-blue text — the secondary counterpart to
/// `TactilePrimaryButtonStyle`.
struct TactileSecondaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16
    var fullWidth = true
    var foreground: Color = Theme.brand

    func makeBody(configuration: Configuration) -> some View {
        TactileButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            cornerRadius: cornerRadius,
            fullWidth: fullWidth,
            foreground: foreground,
            fill: Theme.card,
            border: Theme.hairline,
            lip: Theme.lip,
            lipHeight: 2
        )
    }
}

/// Shared rendering for the tactile button styles. A separate view so it can
/// read `isEnabled` and dim disabled buttons.
private struct TactileButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let cornerRadius: CGFloat
    let fullWidth: Bool
    let foreground: Color
    let fill: Color
    let border: Color?
    let lip: Color
    let lipHeight: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        label
            .font(.headline)
            .foregroundStyle(foreground)
            .padding(.horizontal, fullWidth ? 0 : 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: fullWidth ? 52 : 40)
            .background(shape.fill(fill))
            .overlay {
                if let border { shape.strokeBorder(border, lineWidth: 1) }
            }
            .offset(y: isPressed ? lipHeight : 0)
            .background(shape.fill(lip).offset(y: lipHeight))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.spring(duration: 0.16), value: isPressed)
    }
}

/// Tactile answer button for multiple-choice grids, colored by answer state after reveal.
struct AnswerTileButtonStyle: ButtonStyle {
    enum State { case neutral, correct, wrong, dimmed }

    let state: State

    private var fill: Color {
        switch state {
        case .neutral, .dimmed: Theme.card
        case .correct: Theme.correctTint
        case .wrong: Theme.incorrectTint
        }
    }

    private var border: Color {
        switch state {
        case .neutral, .dimmed: Theme.hairline
        case .correct: Theme.correctBorder
        case .wrong: Theme.incorrectBorder
        }
    }

    private var foreground: Color {
        switch state {
        case .neutral: Theme.ink
        case .dimmed: Theme.inkMuted
        case .correct: Theme.correct
        case .wrong: Theme.incorrect
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let pressed = configuration.isPressed
        let highlighted = state == .correct || state == .wrong
        HStack {
            configuration.label
                .frame(maxWidth: .infinity)
            if highlighted {
                Image(systemName: state == .correct ? "checkmark" : "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(border))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(border, lineWidth: highlighted ? 2 : 1))
        .offset(y: pressed ? 2 : 0)
        .background(shape.fill(highlighted ? border : Theme.lip).offset(y: 2))
        .contentShape(shape)
        .animation(.spring(duration: 0.16), value: pressed)
    }
}

// MARK: - Shared Components

/// Multi-select JLPT level toggles in a pill track. Selected levels get a raised
/// white pill with brand-blue text.
struct TactileLevelPicker: View {
    let levels: [String]
    let selected: Set<String>
    /// Shows a leading dot on selected levels (kept in the layout when hidden so
    /// labels don't shift on toggle).
    var showsDot = false
    let onToggle: (String) -> Void
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(levels, id: \.self) { level in
                let isOn = selected.contains(level)
                Button {
                    onToggle(level)
                } label: {
                    HStack(spacing: 5) {
                        if showsDot {
                            Circle()
                                .fill(Theme.brand)
                                .frame(width: scaled(6), height: scaled(6))
                                .opacity(isOn ? 1 : 0)
                        }
                        Text(level)
                            .font(.system(size: scaled(14), weight: isOn ? .bold : .medium))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isOn ? Theme.brand : Theme.inkMuted)
                    .background {
                        if isOn {
                            Capsule()
                                .fill(Theme.card)
                                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                                .shadow(color: .black.opacity(0.06), radius: 2, y: 2)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("JLPT \(level)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.slateTint))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

/// "Unlock the full version" card shown to free users; tapping opens the paywall.
struct UpgradeBanner: View {
    let subtitle: String
    let price: String?
    let action: () -> Void
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: scaled(16), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.brandFill)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock the full version")
                        .font(.system(size: scaled(15), weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: scaled(12)))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                if let price {
                    Text(price)
                        .font(.system(size: scaled(15), weight: .semibold))
                        .foregroundStyle(Theme.brand)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: scaled(12), weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileCardButtonStyle())
    }
}
