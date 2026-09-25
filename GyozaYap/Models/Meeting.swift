import Foundation

/// Who said a line. The mic is you; the call's own audio output is everyone
/// else. On-device diarization can't tell remote voices apart, so they share
/// one label instead of being guessed at.
nonisolated enum Speaker: String, Codable, CaseIterable, Sendable {
    case me
    case others

    var label: String {
        switch self {
        case .me: "Me"
        case .others: "Them"
        }
    }
}

nonisolated struct TranscriptSegment: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var speaker: Speaker
    /// Seconds from the start of the recording.
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// A moment the user flagged during the call ("that was important").
nonisolated struct Bookmark: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var time: TimeInterval
    var label: String
}

nonisolated struct ActionItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var task: String
    var owner: String?
    var due: String?
    var isDone = false
}

nonisolated struct Topic: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var summary: String
}

/// The AI-written part of a meeting.
nonisolated struct MeetingNotes: Codable, Hashable, Sendable {
    var tldr: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [ActionItem]
    var openQuestions: [String]
    var topics: [Topic]
    /// Which engine wrote these notes, shown so the user knows what they got.
    var generatedBy: String
    var generatedAt: Date
}

nonisolated struct Meeting: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var startedAt: Date
    var duration: TimeInterval = 0
    /// Name of the call app that was detected, e.g. "Microsoft Teams".
    var sourceApp: String?
    var segments: [TranscriptSegment] = []
    var bookmarks: [Bookmark] = []
    /// What the user typed during the call.
    var userNotes: String = ""
    var notes: MeetingNotes?

    var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }
}
