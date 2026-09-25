import AVFoundation
import CoreMedia
import Foundation
import Speech

/// macOS 26 on-device transcription with SpeechAnalyzer + SpeechTranscriber.
@available(macOS 26.0, *)
nonisolated final class AnalyzerTranscriber: SourceTranscriber, @unchecked Sendable {
    let inputFormat: AVAudioFormat
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let resultsTask: Task<Void, Never>

    private init(
        inputFormat: AVAudioFormat,
        analyzer: SpeechAnalyzer,
        input: AsyncStream<AnalyzerInput>.Continuation,
        resultsTask: Task<Void, Never>
    ) {
        self.inputFormat = inputFormat
        self.analyzer = analyzer
        self.input = input
        self.resultsTask = resultsTask
    }

    static func make(
        locale requested: Locale,
        status: @escaping @Sendable (String) -> Void,
        onEvent: @escaping @Sendable (TranscriptEvent) -> Void
    ) async throws -> AnalyzerTranscriber {
        guard SpeechTranscriber.isAvailable else { throw TranscriptionError.unavailable }
        let name = TranscriberFactory.displayName(for: requested)
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested)
        guard let locale = supported else {
            throw TranscriptionError.unsupportedLanguage(name)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        // First use of a language downloads its model (system-managed).
        let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        if let installation {
            status("Downloading the \(name) speech model. This happens once…")
            try await installation.downloadAndInstall()
        }

        let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        guard let format = bestFormat else {
            throw TranscriptionError.noAudioFormat
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)

        let resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        onEvent(.final(text: text, start: result.range.start.seconds, end: result.range.end.seconds))
                    } else {
                        onEvent(.partial(text))
                    }
                }
            } catch {
                onEvent(.failed(error.localizedDescription))
            }
        }

        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            input.finish()
            resultsTask.cancel()
            throw error
        }
        return AnalyzerTranscriber(inputFormat: format, analyzer: analyzer, input: input, resultsTask: resultsTask)
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        input.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async {
        input.finish()
        let analyzer = self.analyzer
        // If finalising ever hangs, don't let it hold the saved meeting hostage.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await analyzer.cancelAndFinishNow()
        }
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        watchdog.cancel()
        await resultsTask.value
    }
}
