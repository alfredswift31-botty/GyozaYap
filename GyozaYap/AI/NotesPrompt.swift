import Foundation

/// The wire shape both AI engines produce. Unknown owner/due come back as
/// empty strings (structured output schemas avoid nullable fields).
nonisolated struct NotesPayload: Codable, Sendable {
    nonisolated struct Action: Codable, Sendable {
        var task: String
        var owner: String
        var due: String
    }

    nonisolated struct TopicPayload: Codable, Sendable {
        var title: String
        var summary: String
    }

    var tldr: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [Action]
    var openQuestions: [String]
    var topics: [TopicPayload]

    enum CodingKeys: String, CodingKey {
        case tldr
        case keyPoints = "key_points"
        case decisions
        case actionItems = "action_items"
        case openQuestions = "open_questions"
        case topics
    }

    func meetingNotes(generatedBy: String, at date: Date = Date()) -> MeetingNotes {
        MeetingNotes(
            tldr: tldr.trimmingCharacters(in: .whitespacesAndNewlines),
            keyPoints: Self.clean(keyPoints),
            decisions: Self.clean(decisions),
            actionItems: actionItems.compactMap { action in
                let task = action.task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.isEmpty else { return nil }
                return ActionItem(task: task, owner: Self.optional(action.owner), due: Self.optional(action.due))
            },
            openQuestions: Self.clean(openQuestions),
            topics: topics.compactMap { topic in
                let title = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return Topic(title: title, summary: topic.summary.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            generatedBy: generatedBy,
            generatedAt: date
        )
    }

    private static func clean(_ items: [String]) -> [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders: Set<String> = ["", "none", "n/a", "unknown", "unassigned", "-"]
        return placeholders.contains(trimmed.lowercased()) ? nil : trimmed
    }
}

nonisolated enum NotesPrompt {
    static let system = """
        You turn meeting transcripts into notes for the person who recorded them.
        Lines are "[time] Speaker: text". "Me" is the recording user; "Them" is \
        everyone else on the call (several people may share that label).
        The transcript comes from speech recognition, so expect misheard words; \
        infer the intended meaning, but never invent facts, names, numbers or \
        commitments that aren't supported by the transcript.
        Write in the language the meeting was held in. Be concise and concrete.
        """

    static func notesRequest(meeting: Meeting, transcript: String) -> String {
        var request = "Write notes for the \(meeting.mode.title.lowercased()) \"\(meeting.title)\".\n"
        request += instructions(for: meeting.mode)

        let markers = meeting.bookmarks.sorted { $0.time < $1.time }.map { marker in
            let note = marker.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = note.isEmpty ? "" : " — \(note)"
            return "[\(TranscriptFormatting.timestamp(marker.time))] \(marker.kind.title)\(suffix)"
        }
        if !markers.isEmpty {
            request += """

                The user flagged these moments live; make sure each is reflected in the notes:
                <markers>
                \(markers.joined(separator: "\n"))
                </markers>

                """
        }

        let notes = meeting.userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            request += """

                The user typed these notes during the meeting; treat them as important hints:
                <user_notes>
                \(notes)
                </user_notes>

                """
        }
        request += """

            <transcript>
            \(transcript)
            </transcript>
            """
        return request
    }

    static func instructions(for mode: NotesMode) -> String {
        let common = """
            - tldr: two or three sentences on what this was about and what came out of it.
            - action_items: concrete follow-ups. owner is the person responsible \
            ("Me" if the recording user took it on, a name if one was said, otherwise ""). \
            due is any deadline mentioned, otherwise "". Never invent an owner or date.

            """
        switch mode {
        case .meeting:
            return common + """
                - key_points: the most important points discussed, each ending with its [time].
                - decisions: what was agreed or decided, each ending with its [time]. Empty if none.
                - open_questions: questions raised but not resolved.
                - topics: the main topics in the order they came up, each with a one or two sentence summary.
                """
        case .brainstorm:
            return common + """
                - key_points: every distinct idea raised, with who suggested it and its [time]. \
                Don't drop ideas because they were brief.
                - decisions: ideas the group chose to pursue, with the reasoning given.
                - open_questions: threads that came up but weren't explored.
                - topics: clusters of related ideas; the summary lists the pros and cons raised.
                """
        case .research:
            return common + """
                - key_points: findings, each with a short verbatim quote and its [time].
                - decisions: conclusions the speakers reached.
                - open_questions: questions asked that were not answered, and contradictions or surprises.
                - topics: the themes that came up, each with a one or two sentence summary.
                """
        }
    }

    static func questionRequest(question: String, title: String, transcript: String) -> String {
        """
        Answer the question using only the meeting transcript below. Quote or \
        cite timestamps like [12:34] where helpful. If the transcript doesn't \
        contain the answer, say so plainly.

        <transcript title="\(title)">
        \(transcript)
        </transcript>

        Question: \(question)
        """
    }

    /// JSON Schema for `NotesPayload`, for Claude structured outputs.
    static var jsonSchema: [String: Any] {
        let stringArray: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let action: [String: Any] = [
            "type": "object",
            "properties": [
                "task": ["type": "string"],
                "owner": ["type": "string"],
                "due": ["type": "string"]
            ],
            "required": ["task", "owner", "due"],
            "additionalProperties": false
        ]
        let topic: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "summary": ["type": "string"]
            ],
            "required": ["title", "summary"],
            "additionalProperties": false
        ]
        return [
            "type": "object",
            "properties": [
                "tldr": ["type": "string"],
                "key_points": stringArray,
                "decisions": stringArray,
                "action_items": ["type": "array", "items": action],
                "open_questions": stringArray,
                "topics": ["type": "array", "items": topic]
            ],
            "required": ["tldr", "key_points", "decisions", "action_items", "open_questions", "topics"],
            "additionalProperties": false
        ]
    }
}
