import AVFoundation
import Foundation

/// Owns one recording's audio sources and their transcribers. Your mic and
/// the call's audio are transcribed separately, which is what makes the
/// "Me" / "Them" labels reliable without guessing voices.
nonisolated final class CaptureSession: @unchecked Sendable {
    nonisolated struct Started: Sendable {
        /// Meeting time zero; transcript times are seconds after this.
        let startedAt: Date
        /// Parts that couldn't start (the recording still runs without them).
        let warnings: [String]
    }

    private let locale: Locale
    private let events: AsyncStream<SourceEvent>.Continuation
    private var microphone: MicrophoneCapture?
    private var systemAudio: SystemAudioCapture?
    private var transcribers: [any SourceTranscriber] = []

    init(locale: Locale, events: AsyncStream<SourceEvent>.Continuation) {
        self.locale = locale
        self.events = events
    }

    /// Starts everything. Throws only if your own microphone can't be
    /// transcribed.
    func start(status: @escaping @Sendable (String) -> Void) async throws -> Started {
        let events = self.events
        var warnings: [String] = []
        let micTimeline = AudioTimeline()
        let callTimeline = AudioTimeline()

        // Transcribers first: the first run may download a speech model.
        let micTranscriber = try await TranscriberFactory.make(locale: locale, status: status) { event in
            events.yield(SourceEvent(speaker: .me, kind: micTimeline.mapped(event)))
        }
        transcribers.append(micTranscriber)

        var callTranscriber: (any SourceTranscriber)?
        do {
            let transcriber = try await TranscriberFactory.make(locale: locale, status: status) { event in
                events.yield(SourceEvent(speaker: .others, kind: callTimeline.mapped(event)))
            }
            transcribers.append(transcriber)
            callTranscriber = transcriber
        } catch {
            warnings.append("Only your side is being transcribed: \(error.localizedDescription)")
        }

        // One shared origin, so both sides' lines interleave by real time.
        let origin = ProcessInfo.processInfo.systemUptime
        let startedAt = Date()
        micTimeline.begin(at: origin)
        callTimeline.begin(at: origin)

        if let callTranscriber {
            let pipe = AudioPipe(outputFormat: callTranscriber.inputFormat, timeline: callTimeline) { buffer in
                callTranscriber.feed(buffer)
            }
            let capture = SystemAudioCapture(pipe: pipe)
            do {
                try capture.start()
                systemAudio = capture
            } catch {
                warnings.append("Only your side is being transcribed: \(error.localizedDescription)")
            }
        }

        let pipe = AudioPipe(outputFormat: micTranscriber.inputFormat, timeline: micTimeline) { buffer in
            micTranscriber.feed(buffer)
        }
        let microphone = MicrophoneCapture(pipe: pipe)
        do {
            try microphone.start()
        } catch {
            await stop()
            throw error
        }
        self.microphone = microphone
        return Started(startedAt: startedAt, warnings: warnings)
    }

    /// Stops capturing, lets the transcribers flush their last words, then
    /// ends the event stream.
    func stop() async {
        microphone?.stop()
        microphone = nil
        systemAudio?.stop()
        systemAudio = nil

        let transcribers = self.transcribers
        self.transcribers = []
        await withTaskGroup(of: Void.self) { group in
            for transcriber in transcribers {
                group.addTask {
                    await transcriber.finish()
                }
            }
        }
        events.finish()
    }
}
