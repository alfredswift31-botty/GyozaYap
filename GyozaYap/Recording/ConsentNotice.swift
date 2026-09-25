import Foundation

nonisolated enum ConsentNotice {
    /// Short message to paste into the call chat before recording.
    static let chatMessage = """
        Heads up: I'm recording and transcribing this call on my Mac for my own \
        notes (GyozaYap, processed on-device). Let me know if you'd rather I didn't.
        """

    /// Why the app asks, shown in the start sheet.
    static let explanation = """
        Many places (including California, Florida, Illinois, Washington, \
        Germany and the EU/UK under GDPR) require everyone on a call to know \
        or agree before it's recorded. Tell people, or paste the notice into \
        the chat. GyozaYap never joins your call as a bot, transcribes on this \
        Mac, and doesn't keep the audio.
        """
}
