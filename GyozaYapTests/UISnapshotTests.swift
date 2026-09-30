import AppKit
import SwiftUI
import Testing
@testable import GyozaYap

/// Renders the real views off screen, in light and dark, and writes PNGs that
/// CI prints into its log. Nobody can run the app on a Mac from CI, so this
/// is how a design change is reviewed before it ships.
@MainActor
enum Snapshot {
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ui-snapshots", isDirectory: true)

    @discardableResult
    static func render<V: View>(_ view: V, name: String, size: CGSize, dark: Bool) throws -> Data {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light))
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = appearance
        host.wantsLayer = true
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        }
        // Render the layer tree: cacheDisplay only captures AppKit drawing and
        // drops SwiftUI's own layers (text and shapes came out blank).
        let scale: CGFloat = 2
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        let layer = try #require(host.layer)
        context.cgContext.scaleBy(x: scale, y: scale)
        // The window background isn't part of the host's layers; without it
        // dark text lands on transparent pixels that the JPEG step turns white.
        var background = NSColor.windowBackgroundColor.cgColor
        appearance?.performAsCurrentDrawingAppearance { background = NSColor.windowBackgroundColor.cgColor }
        context.cgContext.setFillColor(background)
        context.cgContext.fill(CGRect(origin: .zero, size: size))
        // After a display pass AppKit marks the host layer geometry-flipped;
        // render(in:) ignores that on the root, so undo it here.
        if layer.isGeometryFlipped || layer.contentsAreFlipped() {
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context.cgContext)
        context.flushGraphics()
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        window.contentView = nil
        return data
    }
}

/// Realistic sample content: a product team's weekly sync.
@MainActor
enum SnapshotFixtures {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static var meeting: Meeting {
        var meeting = Meeting(title: "Checkout redesign sync", startedAt: start)
        meeting.duration = 31 * 60 + 12
        meeting.sourceApp = "Microsoft Teams"
        meeting.consent = .obtained
        let lines: [(Speaker, Double, String)] = [
            (.others, 4, "Morning. Can we start with the payment step? Support tickets doubled since the last release."),
            (.me, 19, "Yes. Most of them are Apple Pay failing on the second attempt. I can reproduce it on staging."),
            (.others, 41, "Is that the token expiring, or the sheet being dismissed too early?"),
            (.me, 58, "The token. We cache it for ten minutes but the provider now expires it after five."),
            (.others, 84, "Then let's drop the cache to four minutes and ship it on Thursday."),
            (.me, 97, "Agreed. I'll write the patch today and ask Priya to test it tomorrow morning."),
            (.others, 131, "Good. The other open item is the address form. Do we still want to merge line two into line one?"),
            (.me, 152, "Not yet. I'd like to see the drop-off numbers first."),
        ]
        meeting.segments = lines.map { TranscriptSegment(speaker: $0.0, start: $0.1, end: $0.1 + 12, text: $0.2) }
        meeting.bookmarks = [Bookmark(time: 84, kind: .decision, note: "Cache to 4 min, ship Thursday"),
                             Bookmark(time: 152, kind: .question, note: "Address form drop-off")]
        meeting.userNotes = "Ask Priya about staging access."
        meeting.notes = MeetingNotes(
            tldr: "Apple Pay retries fail because the cached payment token outlives the provider's new five-minute expiry. The cache drops to four minutes and ships Thursday.",
            keyPoints: ["Support tickets about payment doubled since the last release [0:04]",
                        "Failures come from an expired cached token, not the payment sheet [0:58]"],
            decisions: ["Reduce the token cache to four minutes and ship on Thursday [1:24]"],
            actionItems: [ActionItem(task: "Write the token cache patch", owner: "Me", due: "Today"),
                          ActionItem(task: "Test the patch on staging", owner: "Priya", due: "Tomorrow morning")],
            openQuestions: ["Should address line two merge into line one? Waiting on drop-off numbers [2:32]"],
            topics: [Topic(title: "Payment failures", summary: "Apple Pay second attempts fail on an expired token."),
                     Topic(title: "Address form", summary: "Merging the address lines is on hold until the drop-off data is in.")],
            generatedBy: "Apple Intelligence (on-device)",
            generatedAt: start.addingTimeInterval(1900))
        return meeting
    }

    static var older: [Meeting] {
        let titles = ["Design review: onboarding", "1:1 with Mara", "Quarterly planning", "Vendor call: Stripe"]
        return titles.enumerated().map { index, title in
            var meeting = Meeting(title: title, startedAt: start.addingTimeInterval(-Double(index + 1) * 86_400 * 1.7))
            meeting.duration = Double([2_280, 1_750, 3_610, 1_140][index])
            if index % 2 == 0 { meeting.notes = Self.meeting.notes }
            return meeting
        }
    }

    struct Environment {
        let store: MeetingStore
        let settings: AppSettings
        let recorder: RecordingController
        let notes: NotesService
    }

    static func environment(meetings: [Meeting]) -> Environment {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-store-\(UUID().uuidString)")
        let store = MeetingStore(directory: directory)
        for meeting in meetings { store.save(meeting) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: "snapshots-\(UUID().uuidString)")!)
        return Environment(store: store, settings: settings,
                           recorder: RecordingController(store: store, settings: settings),
                           notes: NotesService(settings: settings))
    }
}

extension View {
    @MainActor
    func snapshotEnvironment(_ environment: SnapshotFixtures.Environment) -> some View {
        self.environmentObject(environment.store)
            .environmentObject(environment.settings)
            .environmentObject(environment.recorder)
            .environmentObject(environment.notes)
    }
}

/// Serialized: each render spins the run loop, and parallel cases would draw
/// into each other's windows (dark captures came out blank).
@MainActor
@Suite(.serialized)
struct UISnapshotTests {
    private static let window = CGSize(width: 1100, height: 720)

    @Test(arguments: [false, true])
    func emptyLibrary(dark: Bool) throws {
        let environment = SnapshotFixtures.environment(meetings: [])
        try Snapshot.render(RootView().snapshotEnvironment(environment), name: "01-empty-library", size: Self.window, dark: dark)
    }

    @Test(arguments: [false, true])
    func meetingNotes(dark: Bool) throws {
        let meeting = SnapshotFixtures.meeting
        let environment = SnapshotFixtures.environment(meetings: [meeting] + SnapshotFixtures.older)
        try Snapshot.render(RootView(initialSelection: meeting.id).snapshotEnvironment(environment),
                            name: "02-meeting-notes", size: Self.window, dark: dark)
    }

    @Test(arguments: [false, true])
    func meetingTranscript(dark: Bool) throws {
        let meeting = SnapshotFixtures.meeting
        let environment = SnapshotFixtures.environment(meetings: [meeting])
        try Snapshot.render(MeetingDetailView(meetingID: meeting.id, initialTab: .transcript).snapshotEnvironment(environment),
                            name: "03-meeting-transcript", size: CGSize(width: 800, height: 720), dark: dark)
    }

    @Test(arguments: [false, true])
    func meetingAsk(dark: Bool) throws {
        let meeting = SnapshotFixtures.meeting
        let environment = SnapshotFixtures.environment(meetings: [meeting])
        try Snapshot.render(MeetingDetailView(meetingID: meeting.id, initialTab: .ask).snapshotEnvironment(environment),
                            name: "04-meeting-ask", size: CGSize(width: 800, height: 720), dark: dark)
    }

    @Test(arguments: [false, true])
    func recording(dark: Bool) throws {
        let meeting = SnapshotFixtures.meeting
        let environment = SnapshotFixtures.environment(meetings: SnapshotFixtures.older)
        environment.recorder.showPreviewRecording(
            meeting: Meeting(title: meeting.title, startedAt: Date(), sourceApp: "Microsoft Teams"),
            segments: Array(meeting.segments.prefix(6)), markers: meeting.bookmarks,
            partial: [.others: "Good. The other open item is the address"], notes: "Ask Priya about staging access.",
            startedAt: Date().addingTimeInterval(-(2 * 60 + 17)))
        try Snapshot.render(RootView().snapshotEnvironment(environment), name: "05-recording", size: Self.window, dark: dark)
    }

    @Test(arguments: [false, true])
    func startRecordingSheet(dark: Bool) throws {
        let environment = SnapshotFixtures.environment(meetings: [])
        try Snapshot.render(StartRecordingSheet(sourceApp: "Microsoft Teams", onStart: { _, _, _ in }, onCancel: {})
                                .snapshotEnvironment(environment),
                            name: "06-start-sheet", size: CGSize(width: 480, height: 420), dark: dark)
    }

    @Test(arguments: [false, true])
    func settings(dark: Bool) throws {
        let environment = SnapshotFixtures.environment(meetings: [])
        try Snapshot.render(SettingsView().snapshotEnvironment(environment), name: "07-settings",
                            size: CGSize(width: 560, height: 560), dark: dark)
    }

    @Test(arguments: [false, true])
    func recordingToast(dark: Bool) throws {
        try Snapshot.render(RecordingToast(appName: "Microsoft Teams", onStop: {}, onDismiss: {}),
                            name: "08-recording-toast", size: CGSize(width: 360, height: 150), dark: dark)
    }

    /// The library column on its own, with a meeting from today and one from
    /// yesterday added to the fixtures so every kind of group heading shows.
    @Test(arguments: [false, true])
    func sidebar(dark: Bool) throws {
        let meeting = SnapshotFixtures.meeting
        var today = Meeting(title: "Standup", startedAt: Date().addingTimeInterval(-2 * 3_600))
        today.duration = 14 * 60 + 3
        var yesterday = Meeting(title: "Hiring loop debrief: senior iOS engineer", startedAt: Date().addingTimeInterval(-86_400))
        yesterday.duration = 47 * 60 + 38
        yesterday.notes = meeting.notes
        let environment = SnapshotFixtures.environment(meetings: [today, yesterday, meeting] + SnapshotFixtures.older)
        try Snapshot.render(MeetingSidebar(selection: .constant(meeting.id)).snapshotEnvironment(environment),
                            name: "20-sidebar", size: CGSize(width: 280, height: 720), dark: dark)
    }

    /// The main window with a library but nothing selected.
    @Test(arguments: [false, true])
    func noSelection(dark: Bool) throws {
        let environment = SnapshotFixtures.environment(meetings: [SnapshotFixtures.meeting] + SnapshotFixtures.older)
        try Snapshot.render(RootView().snapshotEnvironment(environment), name: "21-no-selection", size: Self.window, dark: dark)
    }

    // TEMPORARY diagnostics: why the detail placeholders render blank.
    @Test(arguments: [false])
    func diagnostics(dark: Bool) throws {
        let state = EmptyState(word: "no meetings", message: "Start a recording.") {
            Button("Start recording") {}.buttonStyle(.primary)
        }
        try Snapshot.render(state, name: "90-diag-plain", size: CGSize(width: 800, height: 400), dark: dark)
        try Snapshot.render(state.background(Theme.canvas), name: "91-diag-canvas", size: CGSize(width: 800, height: 400), dark: dark)
        try Snapshot.render(NavigationSplitView { Text("Side") } detail: { state.background(Theme.canvas) },
                            name: "92-diag-split", size: CGSize(width: 1100, height: 500), dark: dark)
        try Snapshot.render(NavigationSplitView { Text("Side") } detail: {
            VStack(alignment: .leading) { Text("no meetings").displayStyle(); Text("Start a recording.") }
                .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }, name: "93-diag-split-top", size: CGSize(width: 1100, height: 500), dark: dark)
        let environment = SnapshotFixtures.environment(meetings: [SnapshotFixtures.meeting] + SnapshotFixtures.older)
        let size = CGSize(width: 1100, height: 500)
        try Snapshot.render(NavigationSplitView { List { Text("Side") } } detail: {
            EmptyState(word: "no meetings", message: "Start.") { StartAction(style: .primary, isEnabled: true) {} }
                .background(Theme.canvas)
        }, name: "94-diag-startaction", size: size, dark: dark)
        try Snapshot.render(NavigationSplitView { MeetingSidebar(selection: .constant(nil)) } detail: {
            state.background(Theme.canvas)
        }.snapshotEnvironment(environment), name: "95-diag-sidebar", size: size, dark: dark)
        try Snapshot.render(NavigationSplitView { List { Text("Side") } } detail: {
            LibraryOverview(meetings: environment.store.meetings) { StartAction(style: .quiet, isEnabled: true) {} }
        }, name: "96-diag-overview", size: size, dark: dark)
        try Snapshot.render(NavigationSplitView {
            List { Text("Side") }
                .searchable(text: .constant(""), placement: .sidebar, prompt: "Search")
                .toolbar { ToolbarItem { Button("New") {} } }
        } detail: {
            state.background(Theme.canvas)
        }, name: "97-diag-toolbar", size: size, dark: dark)
        let empty = SnapshotFixtures.environment(meetings: [])
        try Snapshot.render(RootView().snapshotEnvironment(empty), name: "98-diag-root-500", size: size, dark: dark)
        try Snapshot.render(NavigationSplitView { Text("Side") } detail: { state.background(Theme.canvas) },
                            name: "99-diag-split-720", size: CGSize(width: 1100, height: 720), dark: dark)
    }
}
