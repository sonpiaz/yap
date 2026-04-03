import AVFoundation
import Combine

class AudioRecorder: ObservableObject {
    static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    @Published var audioLevel: Float = 0.0
    @Published var selectedInputID: String?

    private init() {}

    struct InputDevice: Identifiable, Hashable {
        let id: String
        let name: String
        let deviceID: AudioDeviceID
    }

    func availableInputDevices() -> [InputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard deviceHasInput(deviceID) else { return nil }
            let name = deviceName(deviceID) ?? "Unknown Input"
            return InputDevice(id: String(deviceID), name: name, deviceID: deviceID)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func startRecording() throws {
        let engine = AVAudioEngine()
        if let selectedInputID,
           let deviceID = AudioDeviceID(selectedInputID) {
            try setInputDevice(deviceID)
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Ensure 16kHz mono for Whisper
        guard let convertFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatError
        }

        guard let converter = AVAudioConverter(from: format, to: convertFormat) else {
            throw AudioError.converterError
        }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Convert to 16kHz mono
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / format.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: convertFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            if let channelData = convertedBuffer.floatChannelData?[0] {
                let frames = Int(convertedBuffer.frameLength)
                let rawSamples = Array(UnsafeBufferPointer(start: channelData, count: frames))
                let processedSamples = self.applyNoiseSuppressionIfNeeded(to: rawSamples)

                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: processedSamples)
                self.bufferLock.unlock()

                // Calculate RMS for audio level
                let rms = sqrt(processedSamples.reduce(0) { $0 + $1 * $1 } / Float(max(frames, 1)))
                DispatchQueue.main.async {
                    self.audioLevel = min(1.0, rms * 10)
                }
            }
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
    }

    func stopRecording() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        DispatchQueue.main.async {
            self.audioLevel = 0.0
        }

        return samples
    }

    func runMicrophoneTest(duration: TimeInterval = 2.0) {
        Task { @MainActor in
            do {
                try startRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    _ = self.stopRecording()
                }
            } catch {
                print("[Yap] Mic test failed: \(error)")
            }
        }
    }

    private func applyNoiseSuppressionIfNeeded(to samples: [Float]) -> [Float] {
        let isEnabled = UserDefaults.standard.bool(forKey: "noiseSuppression")
        guard isEnabled else { return samples }

        let gateThreshold: Float = 0.015
        let attenuation: Float = 0.15
        return samples.map { sample in
            abs(sample) < gateThreshold ? sample * attenuation : sample
        }
    }

    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = audioEngine?.inputNode.audioUnit else {
            throw AudioError.inputDeviceUnavailable
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            throw AudioError.inputDeviceUnavailable
        }
    }

    private func deviceHasInput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        return status == noErr ? (name as String) : nil
    }
}

enum AudioError: LocalizedError {
    case formatError
    case converterError
    case permissionDenied
    case inputDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to create audio format"
        case .converterError: return "Failed to create audio converter"
        case .permissionDenied: return "Microphone access denied"
        case .inputDeviceUnavailable: return "Selected input device is unavailable"
        }
    }
}
