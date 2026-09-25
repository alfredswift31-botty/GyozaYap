import Foundation
import Testing
@testable import GyozaYap

struct EchoFilterTests {

    @Test func dropsMicCopiesOfTheOtherSide() {
        let segments = [
            TranscriptSegment(speaker: .others, start: 10, end: 14, text: "We should move the launch to next Thursday"),
            // The mic heard the speakers: same words, slightly garbled.
            TranscriptSegment(speaker: .me, start: 10.4, end: 14.2, text: "we should move the launch to next thursday"),
            TranscriptSegment(speaker: .me, start: 15, end: 17, text: "Sounds good, I'll update the plan")
        ]

        let filtered = EchoFilter.removingEchoes(from: segments)

        #expect(filtered.map(\.text) == [
            "We should move the launch to next Thursday",
            "Sounds good, I'll update the plan"
        ])
    }

    @Test func keepsSimilarWordsSaidMuchLater() {
        let segments = [
            TranscriptSegment(speaker: .others, start: 10, end: 14, text: "We should move the launch to next Thursday"),
            TranscriptSegment(speaker: .me, start: 120, end: 124, text: "We should move the launch to next Thursday")
        ]

        #expect(EchoFilter.removingEchoes(from: segments).count == 2)
    }

    @Test func keepsShortReplies() {
        let segments = [
            TranscriptSegment(speaker: .others, start: 1, end: 2, text: "yes ok"),
            TranscriptSegment(speaker: .me, start: 1, end: 2, text: "yes ok")
        ]

        #expect(EchoFilter.removingEchoes(from: segments).count == 2)
    }

    @Test func keepsEverythingWithoutCallAudio() {
        let segments = [TranscriptSegment(speaker: .me, start: 0, end: 3, text: "Talking to myself about the budget")]

        #expect(EchoFilter.removingEchoes(from: segments) == segments)
    }
}

struct PhraseGroupingTests {

    @Test func splitsAtPausesAndSentenceEnds() {
        let words = [
            PhraseGrouping.Word(text: "Hello", start: 0.0, duration: 0.4),
            PhraseGrouping.Word(text: "everyone.", start: 0.5, duration: 0.5),
            PhraseGrouping.Word(text: "Let's", start: 1.1, duration: 0.3),
            PhraseGrouping.Word(text: "start", start: 1.5, duration: 0.3),
            PhraseGrouping.Word(text: "Budget", start: 4.0, duration: 0.5)
        ]

        let phrases = PhraseGrouping.phrases(from: words, fallbackText: "")

        #expect(phrases.map(\.text) == ["Hello everyone.", "Let's start", "Budget"])
        #expect(phrases[1].start == 1.1)
        #expect(phrases[2].end == 4.5)
    }

    @Test func fallsBackToWholeTextWithoutTimings() {
        let words = [PhraseGrouping.Word(text: "hi", start: 0, duration: 0)]

        let phrases = PhraseGrouping.phrases(from: words, fallbackText: " Hi there ")

        #expect(phrases == [PhraseGrouping.Phrase(text: "Hi there", start: 0, end: 0)])
    }
}

struct TranscriptRetrievalTests {

    @Test func returnsEverythingWhenItFits() {
        let lines = ["[0:01] Me: hello", "[0:02] Them: hi"]

        #expect(TranscriptRetrieval.excerpt(for: "budget?", lines: lines, maxCharacters: 1_000) == lines.joined(separator: "\n"))
    }

    @Test func picksRelevantLinesWithContextInOrder() {
        var lines = (0..<200).map { "[\($0)] Them: filler talk about the weather number \($0)" }
        lines[120] = "[120] Them: the marketing budget is fifty thousand"

        let excerpt = TranscriptRetrieval.excerpt(for: "What is the marketing budget?", lines: lines, maxCharacters: 400)

        #expect(excerpt.contains("marketing budget is fifty thousand"))
        #expect(excerpt.contains("[119]"))
        #expect(excerpt.contains("[121]"))
        #expect(excerpt.count <= 400)
        if let before = excerpt.range(of: "[119]"), let after = excerpt.range(of: "[121]") {
            #expect(before.lowerBound < after.lowerBound)
        } else {
            Issue.record("Expected the neighbouring lines in the excerpt")
        }
    }
}

struct CallAppsTests {

    @Test func recognisesCallAppsAndTheirHelpers() {
        #expect(CallApps.name(forBundleID: "com.microsoft.teams2") == "Microsoft Teams")
        #expect(CallApps.name(forBundleID: "us.zoom.xos") == "Zoom")
        #expect(CallApps.name(forBundleID: "com.google.Chrome.helper") == "Chrome")
        #expect(CallApps.name(forBundleID: "com.apple.WebKit.GPU") == "Safari")
    }

    @Test func ignoresOtherApps() {
        #expect(CallApps.name(forBundleID: "com.apple.VoiceMemos") == nil)
        #expect(CallApps.name(forBundleID: "com.gyoza.GyozaYap") == nil)
    }
}
