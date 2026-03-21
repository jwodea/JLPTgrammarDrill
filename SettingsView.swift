import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale
    @AppStorage(SessionBuilder.newPerSessionKey) private var newPerSession = SessionBuilder.defaultNewPerSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showResetConfirmation = false

    /// Snaps fontScale to the nearest step to avoid floating-point drift.
    private func snapScale() {
        let step = FontSizeManager.step
        fontScale = (fontScale / step).rounded() * step
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        FontSizeManager.scaled(base, scale: fontScale)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $newPerSession, in: 1...5) {
                        HStack {
                            Text("New patterns per session")
                                .font(.system(size: 15))
                            Spacer()
                            Text("\(newPerSession)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Study")
                }

                Section {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Font Size")
                                .font(.system(size: 17, weight: .medium))
                            Spacer()
                            Text("\(Int((fontScale * 100).rounded()))%")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button {
                                fontScale = max(FontSizeManager.minScale, fontScale - FontSizeManager.step)
                                snapScale()
                            } label: {
                                Image(systemName: "textformat.size.smaller")
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                            .disabled(fontScale <= FontSizeManager.minScale + 0.01)

                            Slider(
                                value: $fontScale,
                                in: FontSizeManager.minScale...FontSizeManager.maxScale,
                                step: FontSizeManager.step
                            )
                            .onChange(of: fontScale) {
                                snapScale()
                            }

                            Button {
                                fontScale = min(FontSizeManager.maxScale, fontScale + FontSizeManager.step)
                                snapScale()
                            } label: {
                                Image(systemName: "textformat.size.larger")
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                            .disabled(fontScale >= FontSizeManager.maxScale - 0.01)
                        }

                        Button("Reset to Default") {
                            fontScale = FontSizeManager.defaultScale
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Display")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("日本語の文法")
                            .font(.system(size: scaled(26), weight: .bold))

                        Text("Even if it rains, I will go.")
                            .font(.system(size: scaled(17)))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(["ても", "のに", "けど", "から"], id: \.self) { choice in
                                Text(choice)
                                    .font(.system(size: scaled(17)))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Preview")
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Progress")
                            Spacer()
                        }
                    }
                } footer: {
                    Text("This will erase all SRS data, streak, and study history. Grammar patterns will return to \"New\" status.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Reset All Progress?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetProgress()
                }
            } message: {
                Text("This will permanently delete all your SRS records, streak, and study history. This cannot be undone.")
            }
        }
    }

    private func resetProgress() {
        // Delete all SRS records
        do {
            try modelContext.delete(model: SRSRecord.self)
            try modelContext.save()
        } catch {
            print("Error deleting SRS records: \(error)")
        }

        // Reset UserDefaults keys
        UserDefaults.standard.removeObject(forKey: "streakCount")
        UserDefaults.standard.removeObject(forKey: "lastStudyDate")
    }
}
