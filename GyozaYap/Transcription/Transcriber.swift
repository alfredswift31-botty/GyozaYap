import AVFoundation
import Foundation
import Speech

nonisolated enum TranscriptEvent: Sendable {
    /// Words recognised so far that may still change.
    case partial(String)
    /// Settled text. Times are seconds from the start of that source's audio.
    case final(text: String, start: TimeInterval, end: TimeInterval)
    case failed(String)
}

nonisolated struct SourceEvent: Sendable {
    let speaker: Speaker
    let kind: TranscriptEvent
}

/// One live transcription stream for one audio source.
nonisolated protocol SourceTranscriber: AnyObject, Sendable {
    /// The format `feed` expects.
    var inputFormat: AVAudioFormat { get }
    /// Called from audio threads.
    func feed(_ buffer: AVAudioPCMBuffer)
    /// Flushes remaining audio into final results, then stops.
    func finish() async
}

nonisolated enum TranscriptionError: LocalizedError {
    case unavailable
    case unsupportedLanguage(String)
    case onDeviceUnavailable(String)
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Speech transcription isn't available on this Mac."
        case let .unsupportedLanguage(name):
            "Transcription doesn't support \(name) yet. Pick another language in Settings."
        case let .onDeviceUnavailable(name):
            "On-device transcription for \(name) isn't installed. Turn on Dictation in System Settings › Keyboard to download it, or update to macOS 26."
        case .noAudioFormat:
            "The speech engine didn't accept any audio format."
        }
    }
}

nonisolated enum TranscriberFactory {
    /// Apple's SpeechAnalyzer on macOS 26+, the older on-device
    /// SFSpeechRecognizer before that. Both run entirely on this Mac.
    static func make(
        locale: Locale,
        status: @escaping @Sendable (String) -> Void,
        onEvent: @escaping @Sendable (TranscriptEvent) -> Void
    ) async throws -> any SourceTranscriber {
        if #available(macOS 26.0, *) {
            // Fall back to the older engine on Macs where the new one isn't
            // offered, rather than not transcribing at all.
            if SpeechTranscriber.isAvailable {
                return try await AnalyzerTranscriber.make(locale: locale, status: status, onEvent: onEvent)
            }
        }
        return try LegacyTranscriber(locale: locale, onEvent: onEvent)
    }

    static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

/// Groups timed words into phrases at pauses and sentence ends, so the
/// transcript has natural lines with accurate start times.
nonisolated enum PhraseGrouping {
    nonisolated struct Word: Sendable {
        var text: String
        var start: TimeInterval
        var duration: TimeInterval
    }

    nonisolated struct Phrase: Equatable, Sendable {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
    }

    static func phrases(
        from words: [Word],
        fallbackText: String,
        maxGap: TimeInterval = 0.8,
        maxLength: TimeInterval = 15
    ) -> [Phrase] {
        let usable = words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasTiming = usable.contains { $0.start > 0 || $0.duration > 0 }
        guard hasTiming else {
            let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [Phrase(text: text, start: 0, end: 0)]
        }

        var phrases: [Phrase] = []
        var current: Phrase?
        var lastEnd: TimeInterval = 0
        for word in usable {
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordEnd = word.start + max(word.duration, 0)
            if var phrase = current {
                let endsSentence = phrase.text.last.map { ".?!".contains($0) } ?? false
                if word.start - lastEnd > maxGap || word.start - phrase.start > maxLength || endsSentence {
                    phrases.append(phrase)
                    current = Phrase(text: text, start: word.start, end: wordEnd)
                } else {
                    phrase.text += " " + text
                    phrase.end = max(phrase.end, wordEnd)
                    current = phrase
                }
            } else {
                current = Phrase(text: text, start: word.start, end: wordEnd)
            }
            lastEnd = max(lastEnd, wordEnd)
        }
        if let current {
            phrases.append(current)
        }
        return phrases
    }
}

/// Without headphones, the mic also hears the other side through the
/// speakers, so their words show up twice: once cleanly from call audio
/// ("Them") and once as a muddier copy from the mic ("Me"). This drops the
/// mic copies.
nonisolated enum EchoFilter {
    static func removingEchoes(
        from segments: [TranscriptSegment],
        window: TimeInterval = 3,
        threshold: Double = 0.7
    ) -> [TranscriptSegment] {
        let others = segments
            .filter { $0.speaker == .others }
            .map { (segment: $0, words: words(in: $0.text)) }
        guard !others.isEmpty else { return segments }

        return segments.filter { segment in
            guard segment.speaker == .me else { return true }
            let mine = words(in: segment.text)
            // Too short to judge ("yeah", "ok"); keep it.
            guard mine.count >= 3 else { return true }
            let nearby = others.filter {
                $0.segment.start - window <= segment.end && segment.start <= $0.segment.end + window
            }
            let heard = nearby.reduce(into: Set<String>()) { $0.formUnion($1.words) }
            let overlap = Double(mine.intersection(heard).count) / Double(mine.count)
            return overlap < threshold
        }
    }

    static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 }
        )
    }
}
