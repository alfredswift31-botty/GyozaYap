import AppKit
import SwiftUI
import Testing
@testable import GyozaYap

/// macOS draws the text cursor in the app's accent colour. In 1.1 the dark
/// accent was a graphite as dark as the sidebar's search field, and the
/// cursor vanished there. These keep the accent readable where it's used:
/// as the cursor on a field, and as the fill behind a selected sidebar row.
@MainActor
struct AccentColorTests {
    /// The sidebar search field in dark mode, sampled from a macOS 27 screenshot.
    private static let darkSearchField = NSColor(srgbRed: 0x54 / 255, green: 0x51 / 255, blue: 0x51 / 255, alpha: 1)

    @Test func cursorShowsOnTheDarkSearchField() throws {
        let accent = try Self.accent(dark: true)
        #expect(Self.contrast(accent, Self.darkSearchField) >= 3)
    }

    @Test(arguments: [false, true])
    func cursorShowsOnTextFields(dark: Bool) throws {
        let accent = try Self.accent(dark: dark)
        let field = Self.resolve(NSColor(Theme.surface), dark: dark)
        #expect(Self.contrast(accent, field) >= 3)
    }

    @Test(arguments: [false, true])
    func selectedRowTextReadsOnTheAccent(dark: Bool) throws {
        let accent = try Self.accent(dark: dark)
        let text = Self.resolve(NSColor(Theme.inkInverse), dark: dark)
        #expect(Self.contrast(text, accent) >= 4.5)
    }

    private static func accent(dark: Bool) throws -> NSColor {
        let named = try #require(NSColor(named: "AccentColor"))
        return resolve(named, dark: dark)
    }

    private static func resolve(_ color: NSColor, dark: Bool) -> NSColor {
        var resolved = color
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    /// WCAG contrast ratio between two opaque colours.
    private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ color: NSColor) -> Double {
        func channel(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let c = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }
}
