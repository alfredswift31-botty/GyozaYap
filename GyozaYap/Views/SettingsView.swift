import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var notesService: NotesService

    @State private var keyDraft = ""
    @State private var keyStatus: String?
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Recording") {
                Toggle("Notice when a call starts", isOn: $settings.detectMeetings)
                Toggle("Start recording automatically", isOn: $settings.autoStartRecording)
                    .disabled(!settings.detectMeetings)
                Text(settings.autoStartRecording
                    ? "When Teams, Zoom, Webex, Slack, FaceTime or a browser starts using your microphone, GyozaYap starts recording right away and shows a notice. You're responsible for telling the others."
                    : "When Teams, Zoom, Webex, Slack, FaceTime or a browser starts using your microphone, GyozaYap asks whether to record. It never records without asking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Open GyozaYap at login", isOn: Binding(
                    get: { settings.opensAtLogin },
                    set: { enabled in
                        do {
                            try settings.setOpensAtLogin(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Picker("Default notes style", selection: $settings.defaultMode) {
                    ForEach(NotesMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Transcription language", selection: $settings.transcriptionLocale) {
                    Text("System language").tag("")
                    ForEach(TranscriptionLanguages.common, id: \.id) { language in
                        Text(language.name).tag(language.id)
                    }
                }
            }

            Section("AI notes") {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(NotesEngineChoice.allCases) { Text($0.title).tag($0) }
                }
                if let message = notesService.readinessMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Apple Intelligence writes notes on this Mac: free, private and offline, with nothing to set up. It needs macOS 26 or later on an Apple silicon Mac with Apple Intelligence turned on. Its memory is small, so long meetings are summarised in parts. Claude is optional: it writes stronger notes for very long meetings, but sends the transcript (never audio) to Anthropic using your own API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude API key (optional)") {
                SecureField("sk-ant-…", text: $keyDraft)
                HStack {
                    Button("Save key") {
                        keyStatus = settings.setClaudeKey(keyDraft) ? "Saved to your keychain." : "The keychain refused to save the key."
                        keyDraft = ""
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove key", role: .destructive) {
                        settings.setClaudeKey("")
                        keyStatus = "Key removed."
                    }
                    .disabled(!settings.hasClaudeKey)
                    Spacer()
                    Text(settings.hasClaudeKey ? "Key saved" : "No key")
                        .foregroundStyle(.secondary)
                }
                if let keyStatus {
                    Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

nonisolated enum TranscriptionLanguages {
    nonisolated struct Language: Sendable {
        let id: String
        let name: String
    }

    static let common: [Language] = [
        Language(id: "en-US", name: "English (US)"),
        Language(id: "en-GB", name: "English (UK)"),
        Language(id: "en-AU", name: "English (Australia)"),
        Language(id: "en-IN", name: "English (India)"),
        Language(id: "de-DE", name: "German"),
        Language(id: "es-ES", name: "Spanish (Spain)"),
        Language(id: "es-MX", name: "Spanish (Mexico)"),
        Language(id: "fr-FR", name: "French"),
        Language(id: "it-IT", name: "Italian"),
        Language(id: "ja-JP", name: "Japanese"),
        Language(id: "ko-KR", name: "Korean"),
        Language(id: "pt-BR", name: "Portuguese (Brazil)"),
        Language(id: "zh-CN", name: "Chinese (Mandarin, Simplified)")
    ]
}
