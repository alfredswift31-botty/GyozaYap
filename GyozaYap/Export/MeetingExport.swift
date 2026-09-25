import Foundation

nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case pdf
    case text
    case subtitles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown (.md)"
        case .pdf: "PDF"
        case .text: "Plain text (.txt)"
        case .subtitles: "Subtitles (.srt)"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .pdf: "pdf"
        case .text: "txt"
        case .subtitles: "srt"
        }
    }
}

/// Text renderings of a meeting. PDF is built from `markdown` by `PDFExport`.
nonisolated enum MeetingExport {
    static func markdown(_ meeting: Meeting, includeTranscript: Bool = true) -> String {
        var out = frontMatter(meeting)
        out += "# \(meeting.title)\n\n"
        out += "*\(dateLine(meeting))*\n\n"

        if let notes = meeting.notes {
            out += "## TL;DR\n\n\(notes.tldr)\n\n"
            out += section("Decisions", notes.decisions)
            if !notes.actionItems.isEmpty {
                out += "## Action items\n\n"
                for item in notes.actionItems {
                    var line = "- [\(item.isDone ? "x" : " ")] "
                    if let owner = item.owner {
                        line += "**\(owner):** "
                    }
                    line += item.task
                    if let due = item.due {
                        line += " — due \(due)"
                    }
                    out += line + "\n"
                }
                out += "\n"
            }
            out += section(keyPointsTitle(meeting.mode), notes.keyPoints)
            out += section("Open questions", notes.openQuestions)
            if !notes.topics.isEmpty {
                out += "## Topics\n\n"
                for topic in notes.topics {
                    out += "### \(topic.title)\n\n\(topic.summary)\n\n"
                }
            }
        }

        if !meeting.bookmarks.isEmpty {
            out += "## Marked moments\n\n"
            for marker in meeting.bookmarks.sorted(by: { $0.time < $1.time }) {
                let note = marker.note.isEmpty ? "" : " \(marker.note)"
                out += "- \(marker.kind.symbol) [\(TranscriptFormatting.timestamp(marker.time))] \(marker.kind.title)\(note)\n"
            }
            out += "\n"
        }

        let userNotes = meeting.userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userNotes.isEmpty {
            out += "## My notes\n\n\(userNotes)\n\n"
        }

        if includeTranscript, !meeting.segments.isEmpty {
            out += "## Transcript\n\n"
            for turn in TranscriptFormatting.mergedTurns(meeting.segments) {
                out += "**\(turn.speaker.label)** [\(TranscriptFormatting.timestamp(turn.start))]: \(turn.text)\n\n"
            }
        }
        if let notes = meeting.notes {
            out += "---\n\n*Notes by \(notes.generatedBy). Made with GyozaYap.*\n"
        }
        return out
    }

    static func plainText(_ meeting: Meeting) -> String {
        var out = "\(meeting.title)\n\(dateLine(meeting))\n\n"
        for turn in TranscriptFormatting.mergedTurns(meeting.segments) {
            out += "[\(TranscriptFormatting.timestamp(turn.start))] \(turn.speaker.label): \(turn.text)\n"
        }
        return out
    }

    static func subtitles(_ meeting: Meeting) -> String {
        let cues = meeting.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        return cues.enumerated().map { index, cue in
            let end = max(cue.end, cue.start + 0.5)
            return """
                \(index + 1)
                \(TranscriptFormatting.srtTimestamp(cue.start)) --> \(TranscriptFormatting.srtTimestamp(end))
                \(cue.speaker.label): \(cue.text.trimmingCharacters(in: .whitespacesAndNewlines))

                """
        }.joined(separator: "\n")
    }

    /// A safe file name from the meeting title and date.
    static func fileName(for meeting: Meeting, format: ExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = meeting.title.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Meeting" : String(cleaned.prefix(80))
        return "\(formatter.string(from: meeting.startedAt)) \(base).\(format.fileExtension)"
    }

    static func keyPointsTitle(_ mode: NotesMode) -> String {
        switch mode {
        case .meeting: "Key points"
        case .brainstorm: "Ideas"
        case .research: "Findings"
        }
    }

    private static func section(_ title: String, _ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        return "## \(title)\n\n" + items.map { "- \($0)\n" }.joined() + "\n"
    }

    private static func dateLine(_ meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        var parts = [formatter.string(from: meeting.startedAt), TranscriptFormatting.timestamp(meeting.duration)]
        if let app = meeting.sourceApp {
            parts.append(app)
        }
        return parts.joined(separator: " · ")
    }

    private static func frontMatter(_ meeting: Meeting) -> String {
        let iso = ISO8601DateFormatter()
        var lines = [
            "---",
            "title: \(yamlString(meeting.title))",
            "date: \(iso.string(from: meeting.startedAt))",
            "duration_minutes: \(Int((meeting.duration / 60).rounded()))",
            "mode: \(meeting.mode.rawValue)",
            "consent: \(meeting.consent.rawValue)"
        ]
        if let app = meeting.sourceApp {
            lines.append("app: \(yamlString(app))")
        }
        lines.append("tags: [meeting, gyozayap]")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n\n"
    }

    /// Double-quoted YAML scalar with backslashes and quotes escaped.
    static func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}
