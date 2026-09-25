import Combine
import Foundation

/// Known call apps, matched by bundle ID prefix so helper processes (which
/// often do the actual audio work) count too.
nonisolated enum CallApps {
    static let known: [(prefix: String, name: String)] = [
        ("com.microsoft.teams", "Microsoft Teams"),
        ("us.zoom.xos", "Zoom"),
        ("Cisco-Systems.Spark", "Webex"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("com.webex.meetingmanager", "Webex"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.hnc.Discord", "Discord"),
        ("com.google.Chrome", "Chrome"),
        ("com.microsoft.edgemac", "Edge"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.brave.Browser", "Brave"),
        ("org.mozilla.firefox", "Firefox"),
        // Safari's microphone capture runs in WebKit's media process.
        ("com.apple.Safari", "Safari"),
        ("com.apple.WebKit.GPU", "Safari")
    ]

    static func name(forBundleID bundleID: String) -> String? {
        known.first { bundleID.hasPrefix($0.prefix) }?.name
    }

    /// Names of call apps currently using a microphone.
    static func appsUsingMicrophone() -> Set<String> {
        Set(CoreAudioProperty.bundleIDsUsingInput().compactMap(name(forBundleID:)))
    }
}

/// Notices when a call app starts using the microphone and asks, once per
/// call, whether to record. It never starts recording by itself unless the
/// user turned on auto-start.
@MainActor
final class MeetingDetector {
    var onCallDetected: ((String) -> Void)?
    var shouldPrompt: () -> Bool = { true }

    /// Apps already handled during their current microphone session.
    private var handled = Set<String>()
    private var timer: AnyCancellable?

    func start() {
        timer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.poll()
            }
    }

    func stop() {
        timer = nil
    }

    private func poll() {
        let active = CallApps.appsUsingMicrophone()
        // Forget apps that hung up, so their next call prompts again.
        handled.formIntersection(active)
        let new = active.subtracting(handled)
        guard !new.isEmpty else { return }
        // Recording already, or detection is off: remember these calls
        // without prompting, so they don't pop up later mid-call.
        handled.formUnion(new)
        guard shouldPrompt(), let app = new.sorted().first else { return }
        onCallDetected?(app)
    }
}
