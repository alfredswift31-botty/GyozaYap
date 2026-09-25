import Foundation
import Testing
@testable import GyozaYap

struct TranscriptFormattingTests {

    @Test func formatsTimestamps() {
        #expect(TranscriptFormatting.timestamp(0) == "0:00")
        #expect(TranscriptFormatting.timestamp(245.9) == "4:05")
        #expect(TranscriptFormatting.timestamp(3845) == "1:04:05")
        #expect(TranscriptFormatting.srtTimestamp(3723.45) == "01:02:03,450")
    }

    @Test func mergesConsecutiveTurnsFromTheSameSpeaker() {
        let segments = [
            TranscriptSegment(speaker: .me, start: 0, end: 2, text: "Hello"),
            TranscriptSegment(speaker: .me, start: 2.5, end: 4, text: "everyone"),
            TranscriptSegment(speaker: .others, start: 4.2, end: 6, text: "Hi"),
            TranscriptSegment(speaker: .me, start: 20, end: 21, text: "Later point")
        ]

        let turns = TranscriptFormatting.mergedTurns(segments)

        #expect(turns.map(\.text) == ["Hello everyone", "Hi", "Later point"])
        #expect(turns[0].end == 4)
    }

    @Test func chunksNeverSplitALineOrExceedTheLimit() {
        let lines = (1...50).map { "Line \($0) with some words" }

        let chunks = TranscriptFormatting.chunks(of: lines, maxCharacters: 120)

        #expect(chunks.allSatisfy { $0.count <= 120 })
        #expect(chunks.joined(separator: "\n") == lines.joined(separator: "\n"))
    }
}
