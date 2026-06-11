import SwiftUI

/// Sheet shown when the user taps a locked item or the upgrade prompt.
/// Single non-consumable IAP, no subscriptions.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    private var errorMessage: String? {
        if case .failed(let msg) = store.state { return msg }
        return nil
    }

    private var isBusy: Bool {
        switch store.state {
        case .purchasing, .restoring, .loading: return true
        default: return false
        }
    }

    private var buyButtonTitle: String {
        if let price = store.displayPrice {
            return "Unlock for \(price)"
        }
        if store.product == nil {
            return "Loading…"
        }
        return "Unlock"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    featuresCard
                    buyButtons
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: scaled(13)))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Text("One-time purchase. No subscription. Works across all your iPhones and iPads signed in with the same Apple ID.")
                        .font(.system(size: scaled(12)))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("Unlock Full Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: store.isUnlocked) { _, unlocked in
                if unlocked { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: scaled(44), weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.accentColor, .purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Full Version")
                .font(.system(size: scaled(28), weight: .heavy, design: .rounded))
            Text("Every JLPT level. Every drill. Forever.")
                .font(.system(size: scaled(14)))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(
                icon: "text.book.closed.fill",
                color: .blue,
                title: "All grammar patterns",
                detail: "Hundreds of patterns across N5 through N1, fully drillable with FSRS scheduling."
            )
            featureRow(
                icon: "mic.fill",
                color: .pink,
                title: "All audio sentences",
                detail: "Every audio-eligible sentence for shadowing and speaking practice."
            )
            featureRow(
                icon: "character.ja",
                color: .orange,
                title: "Particles always included",
                detail: "Particle Practice is free for everyone."
            )
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: scaled(18), weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: scaled(15), weight: .semibold))
                Text(detail)
                    .font(.system(size: scaled(13)))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buyButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await store.purchase() }
            } label: {
                HStack(spacing: 8) {
                    if case .purchasing = store.state {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else if store.product == nil {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(buyButtonTitle)
                        .font(.system(size: scaled(17), weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isBusy || store.product == nil)

            Button {
                Task { await store.restore() }
            } label: {
                HStack(spacing: 8) {
                    if case .restoring = store.state {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text("Restore Purchase")
                        .font(.system(size: scaled(15), weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(.accentColor)
                .cornerRadius(12)
            }
            .disabled(isBusy)
        }
        .padding(.horizontal)
    }
}
