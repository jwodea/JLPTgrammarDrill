import SwiftUI
import SwiftData
import AVFoundation

struct AudioDrillSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AudioDrillSettings.thresholdKey)
    private var threshold = AudioDrillSettings.defaultThreshold
    @AppStorage(AudioDrillSettings.stripFinalCopulaKey)
    private var stripFinalCopula = AudioDrillSettings.defaultStripFinalCopula
    @AppStorage(AudioDrillSettings.dailyNewCardBudgetKey)
    private var dailyNewCardBudget = AudioDrillSettings.defaultDailyNewCardBudget
    @AppStorage(AudioDrillSettings.learningPoolCapKey)
    private var learningPoolCap = AudioDrillSettings.defaultLearningPoolCap
    @AppStorage(AudioDrillSettings.activeLevelsCSVKey)
    private var activeLevelsCSV = AudioDrillSettings.defaultActiveLevelsCSV
    @AppStorage(AudioDrillSettings.voiceIdentifierKey)
    private var voiceIdentifier = AudioDrillSettings.defaultVoiceIdentifier

    @State private var showResetFSRSConfirm = false
    @State private var showDeleteAttemptsConfirm = false
    @State private var japaneseVoices: [AVSpeechSynthesisVoice] = []
    @State private var previewSpeaker = JapaneseSpeaker()

    private var activeLevels: Set<String> {
        Set(activeLevelsCSV.split(separator: ",").map(String.init))
    }

    private func toggleLevel(_ level: String) {
        var current = activeLevels
        if current.contains(level) {
            if current.count > 1 { current.remove(level) }
        } else {
            current.insert(level)
        }
        activeLevelsCSV = AudioDrillSettings.allLevels
            .filter { current.contains($0) }
            .joined(separator: ",")
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        // iOS bakes the quality into voice.name on newer versions (e.g. "Otoya (Enhanced)").
        // Avoid stamping it twice.
        if voice.name.contains("(Enhanced)") || voice.name.contains("(Premium)") {
            return voice.name
        }
        let qualityTag: String
        switch voice.quality {
        case .premium: qualityTag = "Premium"
        case .enhanced: qualityTag = "Enhanced"
        default: qualityTag = "Default"
        }
        return "\(voice.name) (\(qualityTag))"
    }

    private var generosityLabel: String {
        switch threshold {
        case ..<0.60: return "Very generous"
        case ..<0.72: return "Generous"
        case ..<0.82: return "Balanced"
        default: return "Strict"
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(AudioDrillSettings.allLevels, id: \.self) { level in
                    Toggle(level, isOn: Binding(
                        get: { activeLevels.contains(level) },
                        set: { _ in toggleLevel(level) }
                    ))
                }
            } header: { Text("Levels") } footer: {
                Text("Which JLPT levels to include in the audio drill.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Generosity")
                        Spacer()
                        Text("\(Int((threshold * 100).rounded()))% · \(generosityLabel)")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $threshold, in: 0.50...0.95, step: 0.01)
                    HStack {
                        Text("Strict").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("Very generous").font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Toggle("Ignore sentence-final です/ます/だ", isOn: $stripFinalCopula)
            } header: { Text("Matching") } footer: {
                Text("Lower threshold accepts looser pronunciation. The toggle drops trailing copulas like です/ます/だ when comparing.")
            }

            Section {
                Stepper(value: $dailyNewCardBudget, in: 1...30) {
                    HStack {
                        Text("New cards per day")
                        Spacer()
                        Text("\(dailyNewCardBudget)").foregroundColor(.secondary)
                    }
                }
                Stepper(value: $learningPoolCap, in: 5...40) {
                    HStack {
                        Text("Learning pool cap")
                        Spacer()
                        Text("\(learningPoolCap)").foregroundColor(.secondary)
                    }
                }
            } header: { Text("Introduction pacing") } footer: {
                Text("Caps how aggressively new sentences are introduced.")
            }

            Section {
                if japaneseVoices.isEmpty {
                    Text("Using system default voice.")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Voice", selection: $voiceIdentifier) {
                        Text("System default").tag("")
                        ForEach(japaneseVoices, id: \.identifier) { voice in
                            Text(voiceLabel(voice)).tag(voice.identifier)
                        }
                    }
                }
                Button {
                    previewSpeaker.speak("こんにちは。発音の練習をしましょう。")
                } label: {
                    Label("Preview voice", systemImage: "speaker.wave.2.fill")
                }
            } header: { Text("Voice") } footer: {
                Text("Only Enhanced and Premium voices are listed — the compact voices iOS ships with sound noticeably worse. Download better Japanese voices in Settings → Accessibility → Spoken Content → Voices → Japanese.")
            }

            Section {
                NavigationLink {
                    MicrophoneTestView()
                } label: {
                    Label("Microphone test", systemImage: "waveform")
                }
            } header: { Text("Hardware") }

            Section {
                Button(role: .destructive) {
                    showResetFSRSConfirm = true
                } label: {
                    Text("Reset all audio drill progress")
                }
                Button(role: .destructive) {
                    showDeleteAttemptsConfirm = true
                } label: {
                    Text("Delete all attempt history")
                }
            } header: { Text("Danger zone") }
        }
        .navigationTitle("Audio Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            japaneseVoices = JapaneseSpeaker.availableJapaneseVoices()
        }
        .alert("Reset all audio drill progress?", isPresented: $showResetFSRSConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                try? modelContext.delete(model: AudioCard.self)
                try? modelContext.save()
            }
        } message: {
            Text("All scheduling state for the audio drill will be wiped. Attempt history is kept.")
        }
        .alert("Delete all attempt history?", isPresented: $showDeleteAttemptsConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? modelContext.delete(model: AudioAttempt.self)
                try? modelContext.save()
            }
        } message: {
            Text("Every recorded attempt for the audio drill will be removed permanently.")
        }
    }
}

// MARK: - Microphone test

private struct MicrophoneTestView: View {
    @State private var recorder = SFSpeechRecognitionService()
    @State private var phase: Phase = .idle
    @State private var transcription: String = ""
    @State private var errorMessage: String?

    enum Phase { case idle, recording, done }

    var body: some View {
        VStack(spacing: 24) {
            Text("Microphone test")
                .font(.system(size: 22, weight: .bold))

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            switch phase {
            case .idle:
                Button {
                    Task { await record3Seconds() }
                } label: {
                    Label("Record 3 seconds", systemImage: "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
            case .recording:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Recording…").font(.system(size: 13)).foregroundColor(.secondary)
                }
            case .done:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heard:").font(.system(size: 12)).foregroundColor(.secondary)
                    Text(transcription.isEmpty ? "—" : transcription)
                        .font(.system(size: 16, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                Button("Test again") {
                    Task { await record3Seconds() }
                }
                .font(.system(size: 15, weight: .medium))
            }

            Spacer()
        }
        .padding(.top, 32)
        .navigationTitle("Mic Test")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            recorder.cancel()
        }
    }

    private func record3Seconds() async {
        errorMessage = nil
        transcription = ""
        let ok = await recorder.requestAuthorization()
        guard ok else {
            errorMessage = SpeechRecognitionError.permissionDenied.errorDescription
            return
        }
        do {
            try await recorder.startRecording()
            phase = .recording
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let t = try await recorder.stopRecordingAndTranscribe()
            transcription = t.raw
            phase = .done
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .idle
        }
    }
}
