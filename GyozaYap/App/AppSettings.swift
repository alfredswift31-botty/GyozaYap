import Combine
import Foundation
import ServiceManagement

nonisolated enum NotesEngineChoice: String, CaseIterable, Identifiable, Sendable {
    /// Apple Intelligence, or Claude if the user added a key.
    case automatic
    case apple
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic (Apple Intelligence, or Claude if you add a key)"
        case .apple: "Apple Intelligence (on-device)"
        case .claude: "Claude (your API key)"
        }
    }
}

/// User preferences, persisted in UserDefaults. The Claude key lives in the
/// keychain instead (see `KeychainStore`).
@MainActor
final class AppSettings: ObservableObject {
    @Published var engine: NotesEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }
    @Published var defaultMode: NotesMode {
        didSet { defaults.set(defaultMode.rawValue, forKey: Keys.mode) }
    }
    @Published var detectMeetings: Bool {
        didSet { defaults.set(detectMeetings, forKey: Keys.detect) }
    }
    /// Start recording as soon as a call is detected instead of asking.
    @Published var autoStartRecording: Bool {
        didSet { defaults.set(autoStartRecording, forKey: Keys.autoStart) }
    }
    /// BCP-47 identifier, e.g. "en-US". Empty means the system language.
    @Published var transcriptionLocale: String {
        didSet { defaults.set(transcriptionLocale, forKey: Keys.locale) }
    }
    @Published var hasSeenConsentGuide: Bool {
        didSet { defaults.set(hasSeenConsentGuide, forKey: Keys.consentGuide) }
    }
    @Published private(set) var hasClaudeKey: Bool

    private let defaults: UserDefaults

    private enum Keys {
        static let engine = "notesEngine"
        static let mode = "defaultMode"
        static let detect = "detectMeetings"
        static let autoStart = "autoStartRecording"
        static let locale = "transcriptionLocale"
        static let consentGuide = "hasSeenConsentGuide"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engine = NotesEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .automatic
        defaultMode = NotesMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .meeting
        detectMeetings = (defaults.object(forKey: Keys.detect) as? Bool) ?? true
        autoStartRecording = defaults.bool(forKey: Keys.autoStart)
        transcriptionLocale = defaults.string(forKey: Keys.locale) ?? ""
        hasSeenConsentGuide = defaults.bool(forKey: Keys.consentGuide)
        hasClaudeKey = KeychainStore.readAPIKey() != nil
    }

    var locale: Locale {
        transcriptionLocale.isEmpty ? .current : Locale(identifier: transcriptionLocale)
    }

    var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setOpensAtLogin(_ enabled: Bool) throws {
        defer { objectWillChange.send() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func claudeKey() -> String? {
        KeychainStore.readAPIKey()
    }

    @discardableResult
    func setClaudeKey(_ key: String) -> Bool {
        let saved = KeychainStore.saveAPIKey(key)
        hasClaudeKey = KeychainStore.readAPIKey() != nil
        return saved
    }
}
