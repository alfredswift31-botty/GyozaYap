import AVFoundation
import CoreAudio
import Foundation

/// Converts whatever format a capture delivers into the format a transcriber
/// wants, then hands each converted buffer on. One pipe per source; the
/// converter keeps sample-rate state between buffers, so it must not be shared.
nonisolated final class AudioPipe: @unchecked Sendable {
    let outputFormat: AVAudioFormat
    private let sink: @Sendable (AVAudioPCMBuffer) -> Void
    private let lock = NSLock()
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat, sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.outputFormat = outputFormat
        self.sink = sink
    }

    /// Called on audio threads. `buffer` may point at memory that is only
    /// valid during the call, so it is always copied (converted) here.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converter?.primeMethod = .none
        }
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        // A fresh buffer every time: the transcriber may hold on to it.
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        let feeder = BufferFeeder(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            feeder.next(inputStatus)
        }
        guard status != .error, output.frameLength > 0 else { return }
        sink(output)
    }
}

/// Hands the converter one buffer, then reports "no data now" so the
/// converter keeps its state for the next call instead of flushing.
nonisolated final class BufferFeeder: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}

/// Your side of the call.
nonisolated final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let pipe: AudioPipe
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var isRunning = false

    init(pipe: AudioPipe) {
        self.pipe = pipe
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        try startLocked()
        isRunning = true
        // Plugging in a headset or changing the input device stops the engine.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        lock.lock()
        defer { lock.unlock() }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func startLocked() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noMicrophone }
        let pipe = self.pipe
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            pipe.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func restartAfterConfigurationChange() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? startLocked()
    }
}

/// Everyone else on the call: a Core Audio process tap on all system audio
/// (except this app), read through a private aggregate device. Needs the
/// "System Audio Recording" permission, not Screen Recording.
nonisolated final class SystemAudioCapture: @unchecked Sendable {
    private let pipe: AudioPipe
    private let ioQueue = DispatchQueue(label: "com.gyoza.GyozaYap.system-audio", qos: .userInitiated)
    private let controlQueue = DispatchQueue(label: "com.gyoza.GyozaYap.system-audio-control")
    private let lock = NSLock()
    private var tapID = CoreAudioProperty.unknownObject
    private var aggregateID = CoreAudioProperty.unknownObject
    private var procID: AudioDeviceIOProcID?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var isRunning = false

    init(pipe: AudioPipe) {
        self.pipe = pipe
    }

    func start() throws {
        lock.lock()
        do {
            try startLocked()
            isRunning = true
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        installDeviceListener()
    }

    func stop() {
        // Remove the listener before taking the lock: removal waits for any
        // in-flight listener call, which itself needs the lock.
        removeDeviceListener()
        lock.lock()
        defer { lock.unlock() }
        isRunning = false
        tearDownLocked()
    }

    private func startLocked() throws {
        let excluded = CoreAudioProperty.processObject(for: getpid()).map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTap = CoreAudioProperty.unknownObject
        try CoreAudioProperty.check(AudioHardwareCreateProcessTap(description, &newTap), "start capturing call audio")
        tapID = newTap

        do {
            let outputDevice = try CoreAudioProperty.read(
                CoreAudioProperty.systemObject,
                kAudioHardwarePropertyDefaultSystemOutputDevice,
                initial: AudioDeviceID(kAudioObjectUnknown)
            )
            let outputUID = try CoreAudioProperty.readString(outputDevice, kAudioDevicePropertyDeviceUID)
            var streamDescription = try CoreAudioProperty.read(
                newTap,
                kAudioTapPropertyFormat,
                initial: AudioStreamBasicDescription()
            )
            guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
                throw CaptureError.unsupportedFormat
            }

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "GyozaYap Call Audio",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapDriftCompensationKey: true,
                        kAudioSubTapUIDKey: description.uuid.uuidString
                    ]
                ]
            ]
            var newAggregate = CoreAudioProperty.unknownObject
            try CoreAudioProperty.check(
                AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate),
                "set up the call audio device"
            )
            aggregateID = newAggregate

            let pipe = self.pipe
            var newProc: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&newProc, newAggregate, ioQueue) { _, inputData, _, _, _ in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else {
                    return
                }
                pipe.process(buffer)
            }
            try CoreAudioProperty.check(status, "read call audio")
            procID = newProc
            try CoreAudioProperty.check(AudioDeviceStart(newAggregate, newProc), "start the call audio device")
        } catch {
            tearDownLocked()
            throw error
        }
    }

    private func tearDownLocked() {
        if aggregateID != CoreAudioProperty.unknownObject {
            if let procID {
                _ = AudioDeviceStop(aggregateID, procID)
                _ = AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != CoreAudioProperty.unknownObject {
            _ = AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = CoreAudioProperty.unknownObject
        tapID = CoreAudioProperty.unknownObject
    }

    /// Switching output (e.g. connecting AirPods mid-call) invalidates the
    /// aggregate device, so rebuild the tap on the new device.
    private func installDeviceListener() {
        var propertyAddress = CoreAudioProperty.makeAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.restartAfterDeviceChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(CoreAudioProperty.systemObject, &propertyAddress, controlQueue, listener)
        if status == noErr {
            deviceListener = listener
        }
    }

    private func removeDeviceListener() {
        guard let deviceListener else { return }
        var propertyAddress = CoreAudioProperty.makeAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
        _ = AudioObjectRemovePropertyListenerBlock(CoreAudioProperty.systemObject, &propertyAddress, controlQueue, deviceListener)
        self.deviceListener = nil
    }

    private func restartAfterDeviceChange() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        tearDownLocked()
        try? startLocked()
    }
}
