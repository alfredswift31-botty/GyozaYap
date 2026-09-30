import AppKit
import SwiftUI

/// A small always-on-top panel in the top-right corner, shown over full-screen
/// calls without stealing focus from the call app.
@MainActor
final class FloatingPanel {
    private(set) var panel: NSPanel?
    private var autoCloseTask: Task<Void, Never>?

    func show<Content: View>(_ content: Content, autoCloseAfter seconds: Double? = 120) {
        close()

        // Measure once, then keep SwiftUI away from the panel's frame.
        // Letting SwiftUI size the panel loops on macOS 27: each frame
        // change moves the title bar's safe area, which asks for new
        // constraints, which moves the frame again, until AppKit throws and
        // the app aborts. Turning off sizingOptions isn't enough: as the
        // window's content view, NSHostingView still resized the panel by the
        // title bar's height (CI saw 370 pt become 402 pt). So the SwiftUI
        // view sits inside a plain container and follows it by autoresizing.
        // The content has a fixed width and doesn't change height, so one
        // measurement is enough. It ignores the safe area so the measured
        // size is the drawn size; the top padding leaves room for the close
        // button.
        let hostingView = NSHostingView(rootView: content.ignoresSafeArea())
        let size = hostingView.fittingSize
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.addSubview(hostingView)

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
        panel.contentView = container
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
/// Fixed width; the panel measures it once, so nothing here changes height.
struct MessageToast: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.live)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.Typeface.heading)
            Text(message)
                .font(Theme.Typeface.meta)
                .lineSpacing(2)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("OK", action: onDismiss)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Theme.Space.s)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xxl)
        .padding(.bottom, Theme.Space.l)
        .frame(width: 360, alignment: .leading)
    }
}

/// Shown when a recording started from the corner panel. Fixed width; the
/// panel measures it once, so nothing here changes height.
struct RecordingToast: View {
    let appName: String
    let onStop: () -> Void
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                LiveDot()
                Text("Recording your \(appName) call")
                    .font(Theme.Typeface.heading)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Let the others know. Transcription happens on this Mac.")
                .font(Theme.Typeface.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.s) {
                Button(copied ? "Copied" : "Copy notice") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(ConsentNotice.chatMessage, forType: .string)
                    copied = true
                }
                .buttonStyle(.quiet)
                Spacer(minLength: Theme.Space.s)
                Button("Stop", role: .destructive, action: onStop)
                    .buttonStyle(.live)
                Button("OK", action: onDismiss)
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Theme.Space.s)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xxl)
        .padding(.bottom, Theme.Space.l)
        .frame(width: 360, alignment: .leading)
    }
}
