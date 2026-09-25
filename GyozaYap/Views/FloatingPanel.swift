import AppKit
import SwiftUI

/// A small always-on-top panel in the top-right corner, shown over full-screen
/// calls without stealing focus from the call app.
@MainActor
final class FloatingPanel {
    private var panel: NSPanel?
    private var autoCloseTask: Task<Void, Never>?

    func show<Content: View>(_ content: Content, autoCloseAfter seconds: Double? = 120) {
        close()

        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        let size = controller.view.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = controller
        panel.setContentSize(size)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 16, y: visible.maxY - frame.height - 16))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        if let seconds {
            autoCloseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                // Leave it alone while the user is typing in it.
                guard !Task.isCancelled, let self, self.panel === panel, !panel.isKeyWindow else { return }
                self.close()
            }
        }
    }

    func close() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// A short message with an OK button, for errors outside the main window.
struct MessageToast: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("OK", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 16)
        .frame(width: 360)
    }
}

/// Shown when a recording started from the corner panel.
struct RecordingToast: View {
    let appName: String
    let onStop: () -> Void
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recording your \(appName) call", systemImage: "record.circle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("Let the others know. Transcription happens on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(copied ? "Copied" : "Copy notice") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(ConsentNotice.chatMessage, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Stop", role: .destructive, action: onStop)
                Button("OK", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 16)
        .frame(width: 360)
    }
}
