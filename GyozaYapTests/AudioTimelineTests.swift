import Foundation
import Testing
@testable import GyozaYap

struct AudioTimelineTests {

    /// Feeds one-second buffers, each finishing at the given uptimes.
    private func feed(_ timeline: AudioTimeline, endingAt uptimes: [TimeInterval]) {
        for uptime in uptimes {
            timeline.noteFed(duration: 1, endingAt: uptime)
        }
    }

    @Test func continuousAudioMapsOneToOne() {
        let timeline = AudioTimeline()
        timeline.begin(at: 100)
        feed(timeline, endingAt: [101, 102, 103, 104, 105])

        #expect(timeline.meetingTime(forAudioTime: 0) == 0)
        #expect(timeline.meetingTime(forAudioTime: 3.5) == 3.5)
    }

    @Test func quietStretchesShiftLaterSpeechForward() {
        let timeline = AudioTimeline()
        timeline.begin(at: 0)
        // Ten seconds of audio, then nothing for twenty, then more audio.
        feed(timeline, endingAt: Array(stride(from: 1.0, through: 10.0, by: 1.0)))
        feed(timeline, endingAt: [31, 32, 33])

        #expect(timeline.meetingTime(forAudioTime: 5) == 5)
        #expect(timeline.meetingTime(forAudioTime: 10) == 30)
        #expect(timeline.meetingTime(forAudioTime: 12) == 32)
    }

    @Test func smallDeliveryJitterIsIgnored() {
        let timeline = AudioTimeline()
        timeline.begin(at: 0)
        feed(timeline, endingAt: [1, 2.2, 3.1, 4.3, 5])

        #expect(timeline.meetingTime(forAudioTime: 4) == 4)
    }

    @Test func aLateFirstBufferStartsLater() {
        let timeline = AudioTimeline()
        timeline.begin(at: 0)
        // The call audio only started flowing 7 seconds into the meeting.
        feed(timeline, endingAt: [8, 9])

        #expect(timeline.meetingTime(forAudioTime: 0) == 7)
        #expect(timeline.meetingTime(forAudioTime: 1.5) == 8.5)
    }

    @Test func finalEventsAreMovedOntoTheMeetingClock() {
        let timeline = AudioTimeline()
        timeline.begin(at: 0)
        feed(timeline, endingAt: [21, 22])

        let mapped = timeline.mapped(.final(text: "hi", start: 0.5, end: 1.5))

        guard case let .final(text, start, end) = mapped else {
            Issue.record("Expected a final event")
            return
        }
        #expect(text == "hi")
        #expect(start == 20.5)
        #expect(end == 21.5)
    }
}
