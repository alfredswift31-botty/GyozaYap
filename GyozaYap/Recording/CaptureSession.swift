import AVFoundation
import Foundation

/// Owns one recording's audio sources and their transcribers. Your mic and
/// the call's audio are transcribed separately, which is what makes the
/// "Me" / "Them" labels reliable without guessing voices.
nonisolated final class CaptureSession: @unchecked Sendable {
    private let locale: Locale
    private let events: AsyncStream<SourceEvent>.Continuation
    private var microphone: MicrophoneCapture?
    private var systemAudio: SystemAudioCapture?
    private var transcribers: [any SourceTranscriber] = []

    init(locale: Locale, events: AsyncStream<SourceEvent>.Continuation) {
        self.locale = locale
        self.events = events
    }

    /// Starts everything. Returns warnings for parts that couldn't start;
    /// throws only if your own microphone can't be transcribed.
    func start(status: @escaping @Sendable (String) -> Void) async throws -> [String] {
        let events = self.events
        var warnings: [String] = []

        let micTranscriber = try await TranscriberFactory.make(locale: locale, status: status) { event in
            events.yield(SourceEvent(speaker: .me, kind: event))
        }
        transcribers.append(micTranscriber)

        do {
            let callTranscriber = try await TranscriberFactory.make(locale: locale, status: status) { event in
                events.yield(SourceEvent(speaker: .others, kind: event))
            }
            transcribers.append(callTranscriber)
            let pipe = AudioPipe(outputFormat: callTranscriber.inputFormat) { buffer in
                callTranscriber.feed(buffer)
            }
            let capture = SystemAudioCapture(pipe: pipe)
            try capture.start()
            systemAudio = capture
        } catch {
            warnings.append("Only your side is being transcribed: \(error.localizedDescription)")
        }

        let pipe = AudioPipe(outputFormat: micTranscriber.inputFormat) { buffer in
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
        return warnings
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
