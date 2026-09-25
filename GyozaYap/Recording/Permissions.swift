import AVFoundation
import Foundation
import Speech

nonisolated enum PermissionError: LocalizedError {
    case microphone
    case speechRecognition

    var errorDescription: String? {
        switch self {
        case .microphone:
            "GyozaYap needs the microphone to hear your side. Allow it in System Settings › Privacy & Security › Microphone."
        case .speechRecognition:
            "GyozaYap needs Speech Recognition to transcribe on your Mac. Allow it in System Settings › Privacy & Security › Speech Recognition."
        }
    }
}

nonisolated enum Permissions {
    static func ensureMicrophone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw PermissionError.microphone }
        default:
            throw PermissionError.microphone
        }
    }

    static func ensureSpeechRecognition() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            // The callback arrives on a background queue.
            let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard status == .authorized else { throw PermissionError.speechRecognition }
        default:
            throw PermissionError.speechRecognition
        }
    }
}
