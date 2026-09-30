import AppKit
import SwiftUI

/// Asked before every recording: what to call it, which notes style, and
/// whether the other people know. The answer is saved with the meeting.
///
/// Shown both as a sheet and in the corner `FloatingPanel`, which measures it
/// once: the width is fixed and nothing here may change the height later.
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
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(sourceApp.map { "\($0) is using your microphone" } ?? "New recording")
            Text(sourceApp == nil ? "Start a recording" : "Record this call?")
                .titleStyle()
                .lineLimit(1)
                .padding(.top, Theme.Space.m)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Title").labelStyle()
                TextField("Title", text: $title, prompt: Text(defaultTitle))
                    .textFieldStyle(.plain)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.ink)
                    .labelsHidden()
                    .lineLimit(1)
                    .fieldSurface()
            }
            .padding(.top, Theme.Space.xl)

            HStack(alignment: .top, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Notes style").labelStyle()
                    Picker("Notes style", selection: $mode) {
                        ForEach(NotesMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Do the others know?").labelStyle()
                    Picker("Do the others know?", selection: $consent) {
                        ForEach(ConsentStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.top, Theme.Space.l)

            Text(ConsentNotice.explanation)
                .font(Theme.Typeface.meta)
                .lineSpacing(2)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.l)

            Hairline()
                .padding(.top, Theme.Space.l)

            HStack(spacing: Theme.Space.s) {
                Button(copied ? "Copied" : "Copy chat notice") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(ConsentNotice.chatMessage, forType: .string)
                    copied = true
                }
                .buttonStyle(.quiet)
                .lineLimit(1)
                .help("Copy a notice to paste into the call chat")
                Spacer(minLength: Theme.Space.s)
                Button(sourceApp == nil ? "Cancel" : "Not now", role: .cancel, action: onCancel)
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                Button("Start recording") {
                    settings.hasSeenConsentGuide = true
                    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallback = defaultTitle.isEmpty ? "Meeting" : defaultTitle
                    onStart(trimmed.isEmpty ? fallback : trimmed, mode, consent)
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Theme.Space.l)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xxl)
        .padding(.bottom, Theme.Space.xl)
        .frame(width: 480, alignment: .leading)
        .onAppear {
            mode = settings.defaultMode
            let time = Date().formatted(date: .abbreviated, time: .shortened)
            defaultTitle = sourceApp.map { "\($0) call · \(time)" } ?? "Meeting · \(time)"
        }
    }
}
