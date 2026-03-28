import SwiftUI
import SwiftData

struct SettingsView: View {
    static let enabledLevelsKey = "enabledJLPTLevels"
    static let defaultEnabledLevels = "N5,N4,N3,N2,N1"
    static let combinedDrillsKey = "combinedDrills"
    private static let allLevels = ["N5", "N4", "N3", "N2", "N1"]

    @AppStorage(FontSizeManager.scaleKey) private var fontScale = FontSizeManager.defaultScale
    @AppStorage(SessionBuilder.defaultNewCountKey) private var defaultNewCount = SessionBuilder.defaultNewCount
    @AppStorage(SettingsView.enabledLevelsKey) private var enabledLevelsString = SettingsView.defaultEnabledLevels
    @AppStorage(SettingsView.combinedDrillsKey) private var combinedDrills = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showResetConfirmation = false

    private var enabledLevelsSet: Set<String> {
        Set(enabledLevelsString.split(separator: ",").map(String.init))
    }

    private func toggleLevel(_ level: String) {
        var current = enabledLevelsSet
        if current.contains(level) {
            // Don't allow disabling all levels
            if current.count > 1 {
                current.remove(level)
            }
        } else {
            current.insert(level)
        }
        enabledLevelsString = Self.allLevels.filter { current.contains($0) }.joined(separator: ",")
    }

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
                    Stepper(value: $defaultNewCount, in: 1...5) {
                        HStack {
                            Text("Default new patterns")
                                .font(.system(size: 15))
                            Spacer()
                            Text("\(defaultNewCount)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("Combined drills", isOn: $combinedDrills)
                        .font(.system(size: 15))
                } header: {
                    Text("Study")
                } footer: {
                    if combinedDrills {
                        Text("Grammar and particle exercises will be mixed together in the 文法 tab sessions.")
                    }
                }

                Section {
                    ForEach(Self.allLevels, id: \.self) { level in
                        Toggle(level, isOn: Binding(
                            get: { enabledLevelsSet.contains(level) },
                            set: { _ in toggleLevel(level) }
                        ))
                    }
                } header: {
                    Text("JLPT Levels")
                } footer: {
                    Text("Choose which JLPT levels to include in study sessions.")
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
