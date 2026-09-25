import Foundation
import Testing
@testable import GyozaYap

struct ExportAndAITests {

    private func sampleMeeting() -> Meeting {
        var meeting = Meeting(title: "Launch \"sync\"", startedAt: Date(timeIntervalSince1970: 1_790_000_000))
        meeting.duration = 125
        meeting.sourceApp = "Microsoft Teams"
        meeting.segments = [
            TranscriptSegment(speaker: .me, start: 0, end: 3, text: "Let's ship Friday."),
            TranscriptSegment(speaker: .others, start: 4, end: 7, text: "I'll write the release notes.")
        ]
        meeting.bookmarks = [Bookmark(time: 4, kind: .decision, note: "Ship Friday")]
        meeting.notes = MeetingNotes(
            tldr: "We agreed to ship on Friday.",
            keyPoints: ["Release is on track [0:00]"],
            decisions: ["Ship Friday [0:00]"],
            actionItems: [ActionItem(task: "Write release notes", owner: "Sam", due: "Thursday")],
            openQuestions: [],
            topics: [Topic(title: "Release", summary: "Timing of the launch.")],
            generatedBy: "Test",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        return meeting
    }

    @Test func markdownHasFrontMatterNotesAndTranscript() {
        let markdown = MeetingExport.markdown(sampleMeeting())

        #expect(markdown.hasPrefix("---\ntitle: \"Launch \\\"sync\\\"\"\n"))
        #expect(markdown.contains("app: \"Microsoft Teams\""))
        #expect(markdown.contains("## Decisions\n\n- Ship Friday [0:00]\n"))
        #expect(markdown.contains("- [ ] **Sam:** Write release notes — due Thursday"))
        #expect(markdown.contains("- ✓ [0:04] Decision Ship Friday"))
        #expect(markdown.contains("**Them** [0:04]: I'll write the release notes."))
        #expect(!markdown.contains("## Open questions"))
    }

    @Test func subtitlesAreNumberedSrtCues() {
        let srt = MeetingExport.subtitles(sampleMeeting())

        #expect(srt.hasPrefix("1\n00:00:00,000 --> 00:00:03,000\nMe: Let's ship Friday.\n"))
        #expect(srt.contains("\n2\n00:00:04,000 --> 00:00:07,000\nThem: I'll write the release notes.\n"))
    }

    @Test func fileNamesAreSafe() {
        var meeting = sampleMeeting()
        meeting.title = "Q3/Q4: plan?"

        let name = MeetingExport.fileName(for: meeting, format: .markdown)

        #expect(name.hasSuffix(" Q3-Q4- plan-.md"))
        #expect(!name.contains("/"))
    }

    @Test func notesPayloadDropsPlaceholdersAndBlanks() throws {
        let json = """
            {"tldr": " Short. ", "key_points": ["A", " "], "decisions": [],
             "action_items": [{"task": "Do it", "owner": "unknown", "due": ""},
                              {"task": " ", "owner": "Me", "due": "Friday"}],
             "open_questions": [], "topics": [{"title": "T", "summary": "S"}]}
            """
        let payload = try JSONDecoder().decode(NotesPayload.self, from: Data(json.utf8))

        let notes = payload.meetingNotes(generatedBy: "Test")

        #expect(notes.tldr == "Short.")
        #expect(notes.keyPoints == ["A"])
        #expect(notes.actionItems.count == 1)
        #expect(notes.actionItems[0].owner == nil)
        #expect(notes.actionItems[0].due == nil)
        #expect(notes.topics.map(\.title) == ["T"])
    }

    @Test func claudeResponseParsingChecksStopReason() throws {
        let ok = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Hi"}],"stop_reason":"end_turn"}"#
        #expect(try ClaudeClient.text(fromResponse: Data(ok.utf8)) == "Hi")

        let refused = #"{"content":[],"stop_reason":"refusal"}"#
        #expect(throws: ClaudeClient.ClaudeError.self) {
            try ClaudeClient.text(fromResponse: Data(refused.utf8))
        }
    }

    @Test func notesSchemaRequiresEveryField() throws {
        let schema = NotesPrompt.jsonSchema
        let required = try #require(schema["required"] as? [String])

        #expect(Set(required) == ["tldr", "key_points", "decisions", "action_items", "open_questions", "topics"])
        #expect(JSONSerialization.isValidJSONObject(schema))
    }

    @Test func meetingRoundTripsThroughTheStoreFormat() throws {
        let meeting = sampleMeeting()
        let data = try MeetingStore.makeEncoder().encode(meeting)
        let decoded = try MeetingStore.makeDecoder().decode(Meeting.self, from: data)

        #expect(decoded == meeting)
    }
}
