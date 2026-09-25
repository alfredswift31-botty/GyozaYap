import AppKit
import SwiftUI

/// Asked before every recording: what to call it, which notes style, and
/// whether the other people know. The answer is saved with the meeting.
struct StartRecordingSheet: View {
    let sourceApp: String?
    let onStart: (_ title: String, _ mode: NotesMode, _ consent: ConsentStatus) -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var title = ""
    @State private var mode: NotesMode = .meeting
    @State private var consent: ConsentStatus = .obtained
    @State private var copied = false
    @State private var defaultTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceApp.map { "Record this \($0) call?" } ?? "New recording")
                    .font(.title2.weight(.semibold))
                if let sourceApp {
                    Text("\(sourceApp) is using your microphone.")
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Title")
                        .gridColumnAlignment(.trailing)
                    TextField("Title", text: $title, prompt: Text(defaultTitle))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
                GridRow {
                    Text("Notes style")
                    Picker("Notes style", selection: $mode) {
                        ForEach(NotesMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Do the others know?")
                    Picker("Do the others know?", selection: $consent) {
                        ForEach(ConsentStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ConsentNotice.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(copied ? "Copied — paste it into the call chat" : "Copy a notice for the call chat") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(ConsentNotice.chatMessage, forType: .string)
                        copied = true
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(sourceApp == nil ? "Cancel" : "Not now", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Start recording") {
                    settings.hasSeenConsentGuide = true
                    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallback = defaultTitle.isEmpty ? "Meeting" : defaultTitle
                    onStart(trimmed.isEmpty ? fallback : trimmed, mode, consent)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: 480)
        .onAppear {
            mode = settings.defaultMode
            let time = Date().formatted(date: .abbreviated, time: .shortened)
            defaultTitle = sourceApp.map { "\($0) call · \(time)" } ?? "Meeting · \(time)"
        }
    }
}
