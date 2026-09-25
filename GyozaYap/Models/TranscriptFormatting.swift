import Foundation

nonisolated enum TranscriptFormatting {
    /// "4:05" under an hour, "1:04:05" from an hour up.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// SubRip timestamps: "01:02:03,450".
    static func srtTimestamp(_ seconds: TimeInterval) -> String {
        let millisTotal = max(0, Int((seconds * 1000).rounded()))
        let hours = millisTotal / 3_600_000
        let minutes = (millisTotal % 3_600_000) / 60_000
        let secs = (millisTotal % 60_000) / 1000
        let millis = millisTotal % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }

    /// One line per segment, "[4:05] Me: text". This is also what the AI reads.
    static func plainTranscript(_ segments: [TranscriptSegment]) -> String {
        segments
            .map { "[\(timestamp($0.start))] \($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Merges consecutive segments from the same speaker that are close in
    /// time, so the transcript reads as turns instead of recognizer fragments.
    static func mergedTurns(_ segments: [TranscriptSegment], maxGap: TimeInterval = 2) -> [TranscriptSegment] {
        var turns: [TranscriptSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if var last = turns.last, last.speaker == segment.speaker, segment.start - last.end <= maxGap {
                last.text += " " + text
                last.end = max(last.end, segment.end)
                turns[turns.count - 1] = last
            } else {
                var copy = segment
                copy.text = text
                turns.append(copy)
            }
        }
        return turns
    }

    /// Splits transcript lines into chunks of at most `maxCharacters`, never
    /// splitting a line. Used to fit long meetings into a small on-device
    /// model's context window.
    static func chunks(of lines: [String], maxCharacters: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in lines {
            let piece = line.count > maxCharacters ? String(line.prefix(maxCharacters)) : line
            if !current.isEmpty, current.count + 1 + piece.count > maxCharacters {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? piece : "\n" + piece
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}
