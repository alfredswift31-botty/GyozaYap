import Combine
import Foundation
import FoundationModels

nonisolated enum NotesError: LocalizedError {
    case busy
    case emptyTranscript
    case unavailable(String)
    case appleIntelligence(String)

    var errorDescription: String? {
        switch self {
        case .busy: "Notes for this meeting are already being written."
        case .emptyTranscript: "There's no transcript to make notes from."
        case let .unavailable(message): message
        case let .appleIntelligence(message): message
        }
    }
}

/// Writes AI notes and answers questions, using Apple Intelligence on this Mac
/// by default, or Claude when the user has added their own key.
@MainActor
final class NotesService: ObservableObject {
    @Published private(set) var progress: [Meeting.ID: String] = [:]

    private let settings: AppSettings
    private var settingsObserver: AnyCancellable?

    private enum Engine {
        case apple
        case claude(ClaudeClient)
    }

    init(settings: AppSettings) {
        self.settings = settings
        // Engine readiness depends on settings; refresh views when they change.
        settingsObserver = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func isWorking(on id: Meeting.ID) -> Bool {
        progress[id] != nil
    }

    func progressText(for id: Meeting.ID) -> String {
        progress[id] ?? ""
    }

    /// Why notes can't be generated right now, or nil when they can.
    var readinessMessage: String? {
        switch settings.engine {
        case .claude:
            return settings.hasClaudeKey ? nil : "Add your Claude API key in Settings to use Claude."
        case .apple:
            if case let .unavailable(message) = AppleIntelligenceStatus.current {
                return message
            }
            return nil
        case .automatic:
            if case let .unavailable(message) = AppleIntelligenceStatus.current, !settings.hasClaudeKey {
                return message
            }
            return nil
        }
    }

    var canGenerate: Bool {
        readinessMessage == nil
    }

    func generateNotes(for meeting: Meeting) async throws -> MeetingNotes {
        guard progress[meeting.id] == nil else { throw NotesError.busy }
        guard !meeting.segments.isEmpty else { throw NotesError.emptyTranscript }
        let engine = try resolveEngine()
        progress[meeting.id] = "Starting…"
        defer { progress[meeting.id] = nil }

        switch engine {
        case let .claude(client):
            progress[meeting.id] = "Claude is reading the transcript…"
            let transcript = TranscriptFormatting.plainTranscript(TranscriptFormatting.mergedTurns(meeting.segments))
            let json = try await client.send(
                system: NotesPrompt.system,
                user: NotesPrompt.notesRequest(meeting: meeting, transcript: transcript),
                schema: NotesPrompt.jsonSchema
            )
            let payload = try JSONDecoder().decode(NotesPayload.self, from: Data(json.utf8))
            return payload.meetingNotes(generatedBy: "Claude (\(client.model))")
        case .apple:
            guard #available(macOS 26.0, *) else {
                throw NotesError.unavailable("On-device AI notes need macOS 26 or later.")
            }
            let id = meeting.id
            do {
                return try await AppleNotesEngine().notes(for: meeting) { [weak self] text in
                    self?.progress[id] = text
                }
            } catch {
                throw Self.friendlyAppleError(error)
            }
        }
    }

    func answer(_ question: String, about meeting: Meeting) async throws -> String {
        guard !meeting.segments.isEmpty else { throw NotesError.emptyTranscript }
        switch try resolveEngine() {
        case let .claude(client):
            let transcript = TranscriptFormatting.plainTranscript(TranscriptFormatting.mergedTurns(meeting.segments))
            return try await client.send(
                system: NotesPrompt.system,
                user: NotesPrompt.questionRequest(question: question, title: meeting.title, transcript: transcript)
            )
        case .apple:
            guard #available(macOS 26.0, *) else {
                throw NotesError.unavailable("On-device answers need macOS 26 or later.")
            }
            do {
                return try await AppleNotesEngine().answer(question, about: meeting)
            } catch {
                throw Self.friendlyAppleError(error)
            }
        }
    }

    private func resolveEngine() throws -> Engine {
        let key = settings.claudeKey()
        switch settings.engine {
        case .claude:
            guard let key else { throw NotesError.unavailable("Add your Claude API key in Settings to use Claude.") }
            return .claude(ClaudeClient(apiKey: key))
        case .apple:
            if case let .unavailable(message) = AppleIntelligenceStatus.current {
                throw NotesError.unavailable(message)
            }
            return .apple
        case .automatic:
            if let key {
                return .claude(ClaudeClient(apiKey: key))
            }
            if case let .unavailable(message) = AppleIntelligenceStatus.current {
                throw NotesError.unavailable(message)
            }
            return .apple
        }
    }

    private static func friendlyAppleError(_ error: Error) -> Error {
        guard #available(macOS 26.0, *),
              let generationError = error as? LanguageModelSession.GenerationError else {
            return error
        }
        switch generationError {
        case .guardrailViolation:
            return NotesError.appleIntelligence("Apple Intelligence's safety filter declined part of this transcript. You can try again, or use Claude in Settings.")
        case .exceededContextWindowSize:
            return NotesError.appleIntelligence("This part of the meeting was too long for the on-device model. Try again, or use Claude for very long meetings.")
        case .assetsUnavailable:
            return NotesError.appleIntelligence("Apple Intelligence's model isn't ready yet. Try again in a little while.")
        case .rateLimited, .concurrentRequests:
            return NotesError.appleIntelligence("Apple Intelligence is busy. Try again in a moment.")
        case .unsupportedLanguageOrLocale:
            return NotesError.appleIntelligence("Apple Intelligence doesn't support this meeting's language yet.")
        default:
            return NotesError.appleIntelligence("Apple Intelligence couldn't write notes: \(generationError.localizedDescription)")
        }
    }
}
