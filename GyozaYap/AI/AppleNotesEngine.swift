import Foundation
import FoundationModels

/// Whether Apple's on-device model can be used right now, and if not, what
/// the user can do about it.
enum AppleIntelligenceStatus: Equatable {
    case ready
    case unavailable(String)

    static var current: AppleIntelligenceStatus {
        guard #available(macOS 26.0, *) else {
            return .unavailable("On-device AI notes need macOS 26 or later with Apple Intelligence.")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return .unavailable("Turn on Apple Intelligence in System Settings to make notes on this Mac.")
            case .deviceNotEligible:
                return .unavailable("This Mac can't run Apple Intelligence (it needs Apple silicon).")
            case .modelNotReady:
                return .unavailable("Apple Intelligence is still downloading its model. Try again in a little while.")
            @unknown default:
                return .unavailable("Apple Intelligence isn't available right now.")
            }
        @unknown default:
            return .unavailable("Apple Intelligence isn't available right now.")
        }
    }
}

@available(macOS 26.0, *)
@Generable
nonisolated struct PartNotes {
    @Guide(description: "The most important points in this part, each ending with its [time].", .maximumCount(6))
    var points: [String]

    @Guide(description: "Decisions or agreements made in this part. Empty if none.", .maximumCount(4))
    var decisions: [String]

    @Guide(description: "Follow-up tasks as 'Owner: task, due date'. Leave out the owner or date if nobody said one. Empty if none.", .maximumCount(5))
    var actionItems: [String]

    @Guide(description: "Questions raised in this part that were not answered.", .maximumCount(4))
    var openQuestions: [String]

    @Guide(description: "Short names of the topics discussed.", .maximumCount(4))
    var topics: [String]
}

@available(macOS 26.0, *)
@Generable
nonisolated struct FinalAction {
    @Guide(description: "What needs to be done.")
    var task: String

    @Guide(description: "Who is responsible: 'Me' for the recording user, a name if one was said, otherwise an empty string.")
    var owner: String

    @Guide(description: "The deadline that was mentioned, otherwise an empty string.")
    var due: String
}

@available(macOS 26.0, *)
@Generable
nonisolated struct FinalTopic {
    @Guide(description: "A short topic title.")
    var title: String

    @Guide(description: "One or two sentences on what was said about it.")
    var summary: String
}

@available(macOS 26.0, *)
@Generable
nonisolated struct FinalNotes {
    @Guide(description: "Two or three sentences on what the meeting was about and what came out of it.")
    var tldr: String

    @Guide(description: "The most important points or ideas.", .maximumCount(8))
    var keyPoints: [String]

    @Guide(description: "Decisions or agreements. Empty if none.", .maximumCount(6))
    var decisions: [String]

    @Guide(description: "Concrete follow-up tasks. Never invent an owner or deadline.", .maximumCount(8))
    var actionItems: [FinalAction]

    @Guide(description: "Questions raised but not resolved.", .maximumCount(5))
    var openQuestions: [String]

    @Guide(description: "The main topics in the order they came up.", .maximumCount(6))
    var topics: [FinalTopic]
}

/// Notes and answers from Apple's on-device model. Its context window is
/// about 4,096 tokens for instructions, input and output together, so long
/// meetings are summarised part by part and the part notes are then combined
/// (map-reduce), each step in a fresh session.
@available(macOS 26.0, *)
struct AppleNotesEngine {
    /// Roughly 1,500–2,000 tokens of transcript per part.
    static let partCharacters = 6_000
    /// Input budget for the final pass, leaving room for its output.
    static let finalInputCharacters = 5_000

    func notes(for meeting: Meeting, progress: (String) -> Void) async throws -> MeetingNotes {
        let lines = Self.lines(for: meeting)
        let transcript = lines.joined(separator: "\n")

        var material: String
        if transcript.count <= Self.finalInputCharacters {
            material = "Transcript:\n" + transcript
        } else {
            let parts = TranscriptFormatting.chunks(of: lines, maxCharacters: Self.partCharacters)
            var partNotes: [PartNotes] = []
            for (index, part) in parts.enumerated() {
                progress("Reading part \(index + 1) of \(parts.count)…")
                partNotes += try await summarize(part, label: "Part \(index + 1) of \(parts.count)", mode: meeting.mode, depth: 0)
            }
            material = try await condense(partNotes, mode: meeting.mode, progress: progress)
        }

        progress("Writing notes…")
        do {
            return try await finalNotes(meeting: meeting, material: material)
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else { throw error }
            // Rare: the budget above was still too big for this text.
            material = String(material.prefix(Self.finalInputCharacters / 2))
            return try await finalNotes(meeting: meeting, material: material)
        }
    }

    func answer(_ question: String, about meeting: Meeting) async throws -> String {
        let excerpt = TranscriptRetrieval.excerpt(for: question, lines: Self.lines(for: meeting), maxCharacters: 6_000)
        let session = LanguageModelSession(instructions: """
            You answer questions about a meeting using only the transcript excerpts \
            you are given. Lines are "[time] Speaker: text"; "Me" is the user. Cite \
            [times] where helpful. If the excerpts don't contain the answer, say so.
            """)
        let response = try await session.respond(to: "Transcript excerpts:\n\(excerpt)\n\nQuestion: \(question)")
        return response.content
    }

    // MARK: Steps

    private func summarize(_ text: String, label: String, mode: NotesMode, depth: Int) async throws -> [PartNotes] {
        let session = LanguageModelSession(instructions: Self.partInstructions(mode))
        do {
            let response = try await session.respond(to: "\(label):\n\(text)", generating: PartNotes.self)
            return [response.content]
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error, depth < 3 else { throw error }
            // Split in half and try again.
            let halves = TranscriptFormatting.chunks(
                of: text.components(separatedBy: "\n"),
                maxCharacters: max(text.count / 2, 500)
            )
            var result: [PartNotes] = []
            for half in halves {
                result += try await summarize(half, label: label, mode: mode, depth: depth + 1)
            }
            return result
        }
    }

    /// Combines part notes until they fit the final pass.
    private func condense(_ parts: [PartNotes], mode: NotesMode, progress: (String) -> Void) async throws -> String {
        var current = parts
        var round = 0
        while true {
            let rendered = current.enumerated().map { item in
                Self.render(item.element, label: "Part \(item.offset + 1)")
            }
            let joined = rendered.joined(separator: "\n\n")
            if joined.count <= Self.finalInputCharacters || current.count <= 1 || round >= 4 {
                return "Notes from each part of the meeting:\n" + String(joined.prefix(Self.finalInputCharacters))
            }
            round += 1
            progress("Combining notes…")
            let groups = TranscriptFormatting.chunks(of: rendered, maxCharacters: Self.partCharacters)
            var next: [PartNotes] = []
            for group in groups {
                next += try await summarize(group, label: "Notes from several parts", mode: mode, depth: 0)
            }
            current = next
        }
    }

    private func finalNotes(meeting: Meeting, material: String) async throws -> MeetingNotes {
        let session = LanguageModelSession(instructions: Self.finalInstructions(meeting.mode))
        let response = try await session.respond(to: Self.finalPrompt(meeting: meeting, material: material), generating: FinalNotes.self)
        let notes = response.content
        let payload = NotesPayload(
            tldr: notes.tldr,
            keyPoints: notes.keyPoints,
            decisions: notes.decisions,
            actionItems: notes.actionItems.map { NotesPayload.Action(task: $0.task, owner: $0.owner, due: $0.due) },
            openQuestions: notes.openQuestions,
            topics: notes.topics.map { NotesPayload.TopicPayload(title: $0.title, summary: $0.summary) }
        )
        return payload.meetingNotes(generatedBy: "Apple Intelligence (on-device)")
    }

    // MARK: Prompts

    static func lines(for meeting: Meeting) -> [String] {
        TranscriptFormatting.mergedTurns(meeting.segments).map {
            "[\(TranscriptFormatting.timestamp($0.start))] \($0.speaker.label): \($0.text)"
        }
    }

    private static func partInstructions(_ mode: NotesMode) -> String {
        let focus: String
        switch mode {
        case .meeting: focus = "points, decisions and follow-ups"
        case .brainstorm: focus = "every distinct idea and who suggested it"
        case .research: focus = "findings, with short quotes"
        }
        return """
            You take notes on part of a \(mode.title.lowercased()) transcript. Lines are \
            "[time] Speaker: text"; "Me" is the user and "Them" is everyone else. \
            Capture the \(focus). The text comes from speech recognition, so some \
            words may be misheard. Never invent facts, names or deadlines.
            """
    }

    private static func finalInstructions(_ mode: NotesMode) -> String {
        """
        You write clear, concise notes for the user who recorded a \(mode.title.lowercased()). \
        "Me" is the user and "Them" is everyone else. Only use what is in the \
        material you are given; never invent facts, owners or deadlines.
        """
    }

    private static func finalPrompt(meeting: Meeting, material: String) -> String {
        var prompt = "Write notes for \"\(meeting.title)\".\n"
        let markers = meeting.bookmarks.sorted { $0.time < $1.time }.prefix(20).map {
            "[\(TranscriptFormatting.timestamp($0.time))] \($0.kind.title)\($0.note.isEmpty ? "" : ": \($0.note)")"
        }
        if !markers.isEmpty {
            prompt += "Moments the user marked as important:\n\(markers.joined(separator: "\n"))\n"
        }
        let userNotes = meeting.userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userNotes.isEmpty {
            prompt += "The user's own notes:\n\(userNotes.prefix(1_000))\n"
        }
        return prompt + "\n" + material
    }

    private static func render(_ notes: PartNotes, label: String) -> String {
        var lines = [label]
        func add(_ title: String, _ items: [String]) {
            let cleaned = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !cleaned.isEmpty {
                lines.append("\(title): " + cleaned.joined(separator: "; "))
            }
        }
        add("Points", notes.points)
        add("Decisions", notes.decisions)
        add("Action items", notes.actionItems)
        add("Open questions", notes.openQuestions)
        add("Topics", notes.topics)
        return lines.joined(separator: "\n")
    }
}

/// Picks the transcript lines most related to a question, keeping a little
/// context around each, so a small model can answer from a long meeting.
nonisolated enum TranscriptRetrieval {
    static let stopwords: Set<String> = [
        "the", "and", "for", "are", "was", "what", "did", "does", "who", "when", "where", "why",
        "how", "about", "that", "this", "with", "have", "has", "from", "they", "them", "you",
        "your", "our", "any", "can", "will", "would", "should", "could", "into", "there",
        "their", "been", "were", "which", "said", "say", "tell", "meeting", "call"
    ]

    static func keywords(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopwords.contains($0) }
        )
    }

    static func excerpt(for question: String, lines: [String], maxCharacters: Int) -> String {
        let full = lines.joined(separator: "\n")
        guard full.count > maxCharacters else { return full }

        let terms = keywords(in: question)
        let scores = lines.map { keywords(in: $0).intersection(terms).count }
        let ranked = lines.indices
            .filter { scores[$0] > 0 }
            .sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }

        var chosen = Set<Int>()
        var total = 0
        for index in ranked {
            for neighbor in [index - 1, index, index + 1] where lines.indices.contains(neighbor) && !chosen.contains(neighbor) {
                let cost = lines[neighbor].count + 1
                guard total + cost <= maxCharacters else { continue }
                chosen.insert(neighbor)
                total += cost
            }
            if total >= maxCharacters {
                break
            }
        }
        guard !chosen.isEmpty else { return String(full.prefix(maxCharacters)) }
        return chosen.sorted().map { lines[$0] }.joined(separator: "\n")
    }
}
