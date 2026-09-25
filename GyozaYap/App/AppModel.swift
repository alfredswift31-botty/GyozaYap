import AppKit
import Foundation
import SwiftUI

/// Owns the app's long-lived objects and connects them: call detection
/// prompts, recording, and notes written automatically after each meeting.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let settings: AppSettings
    let store: MeetingStore
    let notesService: NotesService
    let recorder: RecordingController

    private let detector = MeetingDetector()
    private let panel = FloatingPanel()

    private init() {
        let settings = AppSettings()
        let store = MeetingStore()
        self.settings = settings
        self.store = store
        notesService = NotesService(settings: settings)
        recorder = RecordingController(store: store, settings: settings)

        recorder.onMeetingSaved = { [weak self] meeting in
            self?.writeNotesAutomatically(for: meeting)
        }
        detector.shouldPrompt = { [weak self] in
            guard let self else { return false }
            return self.settings.detectMeetings && self.recorder.phase == .idle
        }
        detector.onCallDetected = { [weak self] app in
            self?.callDetected(app)
        }
        detector.start()
    }

    private func callDetected(_ app: String) {
        if settings.autoStartRecording {
            let title = "\(app) call · \(Date().formatted(date: .abbreviated, time: .shortened))"
            startRecordingFromPanel(title: title, mode: settings.defaultMode, consent: .notRecorded, app: app)
            return
        }

        panel.show(
            StartRecordingSheet(
                sourceApp: app,
                onStart: { [weak self] title, mode, consent in
                    self?.startRecordingFromPanel(title: title, mode: mode, consent: consent, app: app)
                },
                onCancel: { [weak self] in self?.panel.close() }
            )
            .environmentObject(settings)
        )
    }

    /// Starts a recording outside the main window (which may be closed), so
    /// the result, good or bad, is shown in the corner panel.
    private func startRecordingFromPanel(title: String, mode: NotesMode, consent: ConsentStatus, app: String) {
        let recorder = self.recorder
        let panel = self.panel
        panel.close()
        Task {
            await recorder.start(title: title, mode: mode, consent: consent, sourceApp: app)
            if recorder.phase == .recording {
                panel.show(
                    RecordingToast(
                        appName: app,
                        onStop: {
                            panel.close()
                            Task { await recorder.stop() }
                        },
                        onDismiss: { panel.close() }
                    ),
                    autoCloseAfter: 30
                )
            } else if let message = recorder.errorMessage {
                recorder.errorMessage = nil
                panel.show(
                    MessageToast(title: "Couldn't record", message: message, onDismiss: { panel.close() }),
                    autoCloseAfter: nil
                )
            }
        }
    }

    /// Writes notes as soon as a meeting is saved, when an engine is ready.
    private func writeNotesAutomatically(for meeting: Meeting) {
        guard meeting.wordCount >= 25, notesService.canGenerate else { return }
        let notesService = self.notesService
        let store = self.store
        Task {
            guard let notes = try? await notesService.generateNotes(for: meeting),
                  var current = store.meeting(id: meeting.id) else { return }
            current.notes = notes
            store.save(current)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.store.flushPendingWrites()
    }

    /// Keep running with the window closed, so calls can still be detected
    /// from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting mid-meeting saves the recording first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let recorder = AppModel.shared.recorder
        guard recorder.phase == .recording || recorder.phase == .stopping else { return .terminateNow }
        Task {
            await recorder.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct MenuBarIcon: View {
    @ObservedObject var recorder: RecordingController

    var body: some View {
        Image(systemName: recorder.phase == .recording ? "record.circle.fill" : "waveform")
    }
}

struct MenuBarContent: View {
    @ObservedObject var recorder: RecordingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch recorder.phase {
        case .recording:
            Text("Recording: \(recorder.liveMeeting?.title ?? "")")
            Button("Stop recording") {
                Task { await recorder.stop() }
            }
        case .starting:
            Text("Starting…")
        case .stopping:
            Text("Saving…")
        case .idle:
            Button("New recording…") {
                showMainWindow()
                recorder.requestStart(sourceApp: nil)
            }
        }
        Button("Open GyozaYap") { showMainWindow() }
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit GyozaYap") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
