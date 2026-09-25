import AudioToolbox
import CoreAudio
import Foundation

nonisolated enum CaptureError: LocalizedError {
    case noMicrophone
    case coreAudio(action: String, status: OSStatus)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .noMicrophone:
            "No microphone is available."
        case let .coreAudio(action, status):
            "Couldn't \(action) (Core Audio error \(status))."
        case .unsupportedFormat:
            "The call audio format isn't supported."
        }
    }
}

/// Thin, typed wrappers over the Core Audio property C API.
nonisolated enum CoreAudioProperty {
    static var systemObject: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }
    static var unknownObject: AudioObjectID { AudioObjectID(kAudioObjectUnknown) }

    static func makeAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw CaptureError.coreAudio(action: action, status: status) }
    }

    /// Reads a plain-data property (numbers, IDs, C structs).
    static func read<Value: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: Value) throws -> Value {
        var propertyAddress = makeAddress(selector)
        var size = UInt32(MemoryLayout<Value>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, pointer)
        }
        try check(status, "read audio property \(selector)")
        return value
    }

    /// Reads a CFString property. Core Audio returns it retained (+1).
    static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var propertyAddress = makeAddress(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value)
        try check(status, "read audio property \(selector)")
        guard let value else { throw CaptureError.coreAudio(action: "read audio property \(selector)", status: status) }
        return value.takeRetainedValue() as String
    }

    /// The Core Audio process object for a PID, if that process has one.
    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var propertyAddress = makeAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var qualifier = pid
        var object = unknownObject
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            systemObject,
            &propertyAddress,
            UInt32(MemoryLayout<pid_t>.size),
            &qualifier,
            &size,
            &object
        )
        guard status == noErr, object != unknownObject else { return nil }
        return object
    }

    /// Every process Core Audio knows about.
    static func processObjects() -> [AudioObjectID] {
        var propertyAddress = makeAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &propertyAddress, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objects = [AudioObjectID](repeating: unknownObject, count: count)
        let status = objects.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return OSStatus(kAudioHardwareUnspecifiedError) }
            return AudioObjectGetPropertyData(systemObject, &propertyAddress, 0, nil, &size, base)
        }
        guard status == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Bundle IDs of processes that are currently recording from an input
    /// device. Needs no extra permission.
    static func bundleIDsUsingInput() -> Set<String> {
        var result = Set<String>()
        for process in processObjects() {
            let isRunningInput = (try? read(process, kAudioProcessPropertyIsRunningInput, initial: UInt32(0))) ?? 0
            guard isRunningInput != 0,
                  let bundleID = try? readString(process, kAudioProcessPropertyBundleID),
                  !bundleID.isEmpty else { continue }
            result.insert(bundleID)
        }
        return result
    }
}
