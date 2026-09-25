import Combine
import Foundation

/// Keeps every meeting as its own JSON file in Application Support, so one
/// corrupt file can't take the whole library with it and nothing ever leaves
/// the Mac unless the user exports or opts into Claude.
@MainActor
final class MeetingStore: ObservableObject {
    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var loadError: String?

    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = support.appendingPathComponent("GyozaYap/Meetings", isDirectory: true)
        }
        load()
    }

    func meeting(id: Meeting.ID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    /// Inserts or replaces the meeting and writes it to disk.
    func save(_ meeting: Meeting) {
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
        } else {
            meetings.append(meeting)
        }
        meetings.sort { $0.startedAt > $1.startedAt }
        write(meeting)
    }

    func delete(_ id: Meeting.ID) {
        meetings.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    /// Case-insensitive search over titles, transcripts, typed notes and AI
    /// notes. Returns the matching meetings, newest first.
    func search(_ query: String) -> [Meeting] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return meetings }
        return meetings.filter { MeetingSearch.matches($0, query: needle) }
    }

    private func load() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let decoder = Self.makeDecoder()
            var loaded: [Meeting] = []
            var unreadable = 0
            for file in files where file.pathExtension == "json" {
                do {
                    loaded.append(try decoder.decode(Meeting.self, from: Data(contentsOf: file)))
                } catch {
                    unreadable += 1
                }
            }
            meetings = loaded.sorted { $0.startedAt > $1.startedAt }
            loadError = unreadable > 0 ? "\(unreadable) meeting file(s) couldn't be read." : nil
        } catch {
            loadError = "Couldn't open the meetings folder: \(error.localizedDescription)"
        }
    }

    private func write(_ meeting: Meeting) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(meeting)
            try data.write(to: fileURL(for: meeting.id), options: .atomic)
        } catch {
            loadError = "Couldn't save “\(meeting.title)”: \(error.localizedDescription)"
        }
    }

    private func fileURL(for id: Meeting.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

nonisolated enum MeetingSearch {
    static func matches(_ meeting: Meeting, query: String) -> Bool {
        let haystacks: [String] = [meeting.title, meeting.userNotes]
            + meeting.segments.map(\.text)
            + (meeting.notes.map { notes in
                [notes.tldr] + notes.keyPoints + notes.decisions + notes.openQuestions
                    + notes.actionItems.map(\.task) + notes.topics.flatMap { [$0.title, $0.summary] }
            } ?? [])
        return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Transcript segments containing the query, for jump-to-moment results.
    static func matchingSegments(in meeting: Meeting, query: String) -> [TranscriptSegment] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return meeting.segments.filter { $0.text.localizedCaseInsensitiveContains(needle) }
    }
}
