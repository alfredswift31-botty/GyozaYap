import AVFoundation
import Foundation
import Speech

/// macOS 15 fallback: on-device SFSpeechRecognizer. Recognition requests are
/// rotated every ~50 seconds of audio so a long meeting never runs into
/// per-request limits, and restarted if the recognizer gives up after a
/// silence.
nonisolated final class LegacyTranscriber: SourceTranscriber, @unchecked Sendable {
    let inputFormat: AVAudioFormat
    private let recognizer: SFSpeechRecognizer
    private let onEvent: @Sendable (TranscriptEvent) -> Void
    private let lock = NSLock()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var endedGenerations = Set<Int>()
    private var framesFed: AVAudioFramePosition = 0
    private var requestStartFrame: AVAudioFramePosition = 0
    private var pendingRequests = 0
    private var isFinishing = false
    private var finishContinuation: CheckedContinuation<Void, Never>?

    private static let rotationSeconds: Double = 50

    init(locale: Locale, onEvent: @escaping @Sendable (TranscriptEvent) -> Void) throws {
        let name = TranscriberFactory.displayName(for: locale)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.unsupportedLanguage(name)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable(name)
        }
        self.recognizer = recognizer
        self.onEvent = onEvent
        inputFormat = SFSpeechAudioBufferRecognitionRequest().nativeAudioFormat

        lock.lock()
        startRequestLocked()
        lock.unlock()
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinishing else { return }
        request?.append(buffer)
        framesFed += AVAudioFramePosition(buffer.frameLength)
        if Double(framesFed - requestStartFrame) / inputFormat.sampleRate >= Self.rotationSeconds {
            request?.endAudio()
            startRequestLocked()
        }
    }

    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            isFinishing = true
            request?.endAudio()
            if pendingRequests == 0 {
                lock.unlock()
                continuation.resume()
                return
            }
            finishContinuation = continuation
            lock.unlock()
            // The last result normally arrives within a second or two.
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.resumeFinish()
            }
        }
        lock.lock()
        task?.cancel()
        task = nil
        request = nil
        lock.unlock()
    }

    private func startRequestLocked() {
        generation += 1
        let myGeneration = generation
        let offset = Double(framesFed) / inputFormat.sampleRate
        requestStartFrame = framesFed
        pendingRequests += 1

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result: result, error: error, generation: myGeneration, offset: offset)
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation: Int, offset: TimeInterval) {
        if let result {
            if result.isFinal {
                let words = result.bestTranscription.segments.map {
                    PhraseGrouping.Word(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                }
                let phrases = PhraseGrouping.phrases(from: words, fallbackText: result.bestTranscription.formattedString)
                for phrase in phrases {
                    onEvent(.final(text: phrase.text, start: offset + phrase.start, end: offset + phrase.end))
                }
                onEvent(.partial(""))
            } else {
                onEvent(.partial(result.bestTranscription.formattedString))
            }
        }

        guard result?.isFinal == true || error != nil else { return }

        lock.lock()
        guard !endedGenerations.contains(generation) else {
            lock.unlock()
            return
        }
        endedGenerations.insert(generation)
        pendingRequests = max(0, pendingRequests - 1)
        // The current request ended on its own (usually after a long
        // silence): start a fresh one so transcription continues.
        if generation == self.generation, !isFinishing {
            startRequestLocked()
        }
        let continuation = (isFinishing && pendingRequests == 0) ? finishContinuation : nil
        if continuation != nil {
            finishContinuation = nil
        }
        lock.unlock()
        continuation?.resume()
    }

    private func resumeFinish() {
        lock.lock()
        let continuation = finishContinuation
        finishContinuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
