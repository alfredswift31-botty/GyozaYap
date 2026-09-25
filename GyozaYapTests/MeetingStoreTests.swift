import Foundation
import Testing
@testable import GyozaYap

@MainActor
struct MeetingStoreTests {

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GyozaYapTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func meeting(_ title: String, at seconds: TimeInterval) -> Meeting {
        var meeting = Meeting(title: title, startedAt: Date(timeIntervalSince1970: seconds))
        meeting.segments = [TranscriptSegment(speaker: .me, start: 0, end: 1, text: "Budget talk")]
        return meeting
    }

    @Test func savedMeetingsSurviveARelaunchNewestFirst() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MeetingStore(directory: directory)
        store.save(meeting("Older", at: 1_000))
        store.save(meeting("Newer", at: 2_000))
        store.flushPendingWrites()

        let reopened = MeetingStore(directory: directory)
        #expect(reopened.meetings.map(\.title) == ["Newer", "Older"])
        #expect(reopened.loadError == nil)
    }

    @Test func rapidEditsAreKeptInMemoryAndWrittenOnce() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MeetingStore(directory: directory)
        var draft = meeting("D", at: 1_000)
        for character in "Draft title" {
            draft.title.append(character)
            store.save(draft)
        }
        #expect(store.meeting(id: draft.id)?.title == "DDraft title")

        store.flushPendingWrites()
        #expect(MeetingStore(directory: directory).meeting(id: draft.id)?.title == "DDraft title")
    }

    @Test func deletingCancelsAPendingWrite() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MeetingStore(directory: directory)
        let doomed = meeting("Doomed", at: 1_000)
        store.save(doomed)
        store.delete(doomed.id)
        store.flushPendingWrites()

        #expect(store.meetings.isEmpty)
        #expect(MeetingStore(directory: directory).meetings.isEmpty)
    }

    @Test func searchLooksInsideTranscripts() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MeetingStore(directory: directory)
        store.save(meeting("Weekly sync", at: 1_000))

        #expect(store.search("budget").map(\.title) == ["Weekly sync"])
        #expect(store.search("roadmap").isEmpty)
        #expect(store.search("  ").count == 1)
    }
}
