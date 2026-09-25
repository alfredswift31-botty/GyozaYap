import Combine
import Foundation

/// Drives one recording at a time: permissions, capture, the live transcript,
/// markers and notes typed during the call, autosave, and the final save.
@MainActor
final class RecordingController: ObservableObject {
    nonisolated enum Phase: Sendable {
        case idle
        case starting
        case recording
        case stopping
    }

    /// A request to show the start sheet (from the toolbar, menu bar or a
    /// detected call).
    nonisolated struct StartRequest: Identifiable, Sendable {
        let id = UUID()
        let sourceApp: String?
    }

    @Published private(set) var phase: Phase = .idle
    /// Title, mode and other metadata of the recording in progress.
    @Published private(set) var liveMeeting: Meeting?
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published private(set) var liveMarkers: [Bookmark] = []
    @Published var liveNotes = ""
    @Published private(set) var partialText: [Speaker: String] = [:]
    @Published private(set) var statusNotes: [String] = []
    @Published private(set) var startingStatus: String?
    @Published private(set) var recordingStartedAt: Date?
    /// Bumped on every new final line, for auto-scrolling.
    @Published private(set) var transcriptRevision = 0
    @Published private(set) var lastSavedMeetingID: Meeting.ID?
    @Published var pendingStart: StartRequest?
    @Published var errorMessage: String?

    /// Called after a finished meeting is saved.
    var onMeetingSaved: ((Meeting) -> Void)?

    private let store: MeetingStore
    private let settings: AppSettings
    private var session: CaptureSession?
    private var eventTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var didShowSystemAudioHint = false

    init(store: MeetingStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func requestStart(sourceApp: String?) {
        guard phase == .idle else { return }
        pendingStart = StartRequest(sourceApp: sourceApp)
    }

    func start(title: String, mode: NotesMode, consent: ConsentStatus, sourceApp: String?) async {
        guard phase == .idle else { return }
        phase = .starting
        startingStatus = "Checking permissions…"
        statusNotes = []
        partialText = [:]
        liveSegments = []
        liveMarkers = []
        liveNotes = ""
        didShowSystemAudioHint = false

        var meeting = Meeting(title: title, startedAt: Date())
        meeting.mode = mode
        meeting.consent = consent
        meeting.sourceApp = sourceApp
        liveMeeting = meeting

        do {
            try await Permissions.ensureMicrophone()
            try await Permissions.ensureSpeechRecognition()
        } catch {
            abortStart(error.localizedDescription)
            return
        }

        startingStatus = "Starting on-device transcription…"
        let (events, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
        let session = CaptureSession(locale: settings.locale, events: continuation)
        let controller = self
        do {
            statusNotes = try await session.start { text in
                Task { @MainActor in
                    controller.startingStatus = text
                }
            }
        } catch {
            continuation.finish()
            abortStart(error.localizedDescription)
            return
        }

        self.session = session
        let startedAt = Date()
        recordingStartedAt = startedAt
        liveMeeting?.startedAt = startedAt
        startingStatus = nil
        phase = .recording

        eventTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
        autosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.autosave()
            }
        }
    }

    func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        guard phase == .recording else { return }
        let task = Task { await performStop() }
        stopTask = task
        await task.value
        stopTask = nil
    }

    func addMarker(_ kind: Bookmark.Kind) {
        guard phase == .recording, let start = recordingStartedAt else { return }
        liveMarkers.append(Bookmark(time: Date().timeIntervalSince(start), kind: kind))
    }

    // MARK: Private

    private func performStop() async {
        let stoppedAt = Date()
        phase = .stopping
        autosaveTask?.cancel()
        autosaveTask = nil

        await session?.stop()
        session = nil
        await eventTask?.value
        eventTask = nil

        if var meeting = composedMeeting(endingAt: stoppedAt) {
            meeting.segments = EchoFilter.removingEchoes(from: meeting.segments)
            store.save(meeting)
            lastSavedMeetingID = meeting.id
            onMeetingSaved?(meeting)
        }

        liveMeeting = nil
        liveSegments = []
        liveMarkers = []
        liveNotes = ""
        partialText = [:]
        statusNotes = []
        recordingStartedAt = nil
        phase = .idle
    }

    private func abortStart(_ message: String) {
        phase = .idle
        liveMeeting = nil
        startingStatus = nil
        errorMessage = message
    }

    private func handle(_ event: SourceEvent) {
        switch event.kind {
        case let .partial(text):
            partialText[event.speaker] = text
        case let .final(text, start, end):
            partialText[event.speaker] = nil
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let safeStart = max(0, start.isFinite ? start : 0)
            let safeEnd = max(safeStart, end.isFinite ? end : safeStart)
            liveSegments.append(TranscriptSegment(speaker: event.speaker, start: safeStart, end: safeEnd, text: trimmed))
            transcriptRevision += 1
        case let .failed(message):
            let source = event.speaker == .me ? "Your microphone" : "Call audio"
            let note = "\(source) stopped transcribing: \(message)"
            if !statusNotes.contains(note) {
                statusNotes.append(note)
            }
        }
    }

    private func composedMeeting(endingAt end: Date) -> Meeting? {
        guard var meeting = liveMeeting else { return nil }
        meeting.segments = liveSegments.sorted { $0.start < $1.start }
        meeting.bookmarks = liveMarkers
        meeting.userNotes = liveNotes
        if let start = recordingStartedAt {
            meeting.duration = max(0, end.timeIntervalSince(start))
        }
        return meeting
    }

    /// Saves the meeting so far, so a crash or power loss loses at most 30 s.
    private func autosave() {
        guard phase == .recording, let meeting = composedMeeting(endingAt: Date()) else { return }
        store.save(meeting)

        let heardMe = meeting.segments.contains { $0.speaker == .me }
        let heardThem = meeting.segments.contains { $0.speaker == .others }
        if !didShowSystemAudioHint, meeting.duration > 120, heardMe, !heardThem {
            didShowSystemAudioHint = true
            statusNotes.append("Not hearing the others? Allow GyozaYap under System Settings › Privacy & Security › Screen & System Audio Recording.")
        }
    }
}
