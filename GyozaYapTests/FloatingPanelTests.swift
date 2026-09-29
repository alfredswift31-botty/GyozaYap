import AppKit
import SwiftUI
import Testing
@testable import GyozaYap

/// The corner panel shown when a call is detected. On macOS 27 it crashed the
/// app when SwiftUI was allowed to size the window; these check that the
/// panel is measured once and then keeps its size through layout passes.
@MainActor
struct FloatingPanelTests {

    @Test func callDetectedPanelKeepsItsMeasuredSize() throws {
        let floating = FloatingPanel()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "FloatingPanelTests-\(UUID().uuidString)")!)
        floating.show(
            StartRecordingSheet(sourceApp: "Zoom", onStart: { _, _, _ in }, onCancel: {})
                .environmentObject(settings),
            autoCloseAfter: nil
        )
        defer { floating.close() }
        let panel = try #require(floating.panel)
        let measured = panel.frame.size
        #expect(measured.width >= 480)
        #expect(measured.height > 200)

        for _ in 0..<5 {
            panel.contentView?.needsLayout = true
            panel.layoutIfNeeded()
            panel.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        #expect(panel.frame.size == measured)
    }

    @Test func toastsShowAndClose() throws {
        let floating = FloatingPanel()
        floating.show(MessageToast(title: "Couldn't record", message: "Test message.", onDismiss: {}), autoCloseAfter: nil)
        let panel = try #require(floating.panel)
        #expect(panel.frame.width >= 360)
        #expect(panel.isVisible)
        floating.close()
        #expect(floating.panel == nil)
    }
}
