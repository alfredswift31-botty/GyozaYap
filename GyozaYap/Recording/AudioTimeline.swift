import Foundation

/// Maps a transcriber's audio time (seconds of audio fed so far) to meeting
/// time (seconds since the recording started).
///
/// The two diverge whenever a source stops delivering audio for a while: the
/// call-audio tap can go quiet when nothing is playing, and a device change
/// restarts capture. Without this, everything the other side said after a
/// quiet stretch would be stamped minutes too early and sorted into the wrong
/// place. Both sources share one origin, so their lines interleave correctly.
nonisolated final class AudioTimeline: @unchecked Sendable {
    /// Wall-clock gaps shorter than this are treated as normal delivery jitter.
    static let gapThreshold: TimeInterval = 0.5

    private let lock = NSLock()
    private var origin: TimeInterval?
    private var audioSeconds: TimeInterval = 0
    /// Points where audio time and meeting time were (re)aligned.
    private var checkpoints: [(audio: TimeInterval, meeting: TimeInterval)] = []

    /// Sets meeting time zero, as a `ProcessInfo.systemUptime` value.
    func begin(at uptime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        origin = uptime
    }

    /// Records that `duration` seconds of audio, captured ending at `uptime`,
    /// were handed to the transcriber.
    func noteFed(duration: TimeInterval, endingAt uptime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard let origin, duration > 0 else { return }
        let meetingStart = uptime - origin - duration
        if let last = checkpoints.last {
            let expected = last.meeting + (audioSeconds - last.audio)
            if meetingStart - expected > Self.gapThreshold {
                checkpoints.append((audio: audioSeconds, meeting: meetingStart))
            }
        } else {
            checkpoints.append((audio: audioSeconds, meeting: max(0, meetingStart)))
        }
        audioSeconds += duration
    }

    /// Meeting time for a point in this source's audio.
    func meetingTime(forAudioTime time: TimeInterval) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let checkpoint = checkpoints.last(where: { $0.audio <= time }) ?? checkpoints.first else {
            return time
        }
        return max(0, checkpoint.meeting + (time - checkpoint.audio))
    }

    /// The same event with its times moved onto the meeting clock.
    func mapped(_ event: TranscriptEvent) -> TranscriptEvent {
        guard case let .final(text, start, end) = event else { return event }
        return .final(text: text, start: meetingTime(forAudioTime: start), end: meetingTime(forAudioTime: end))
    }
}
