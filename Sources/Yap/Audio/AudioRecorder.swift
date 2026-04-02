import AVFoundation
import Combine

class AudioRecorder: ObservableObject {
    static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var levelTimer: Timer?

    @Published var audioLevel: Float = 0.0

    private init() {}

    func startRecording() throws {
        let engine = AVAudioEngine()
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
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))

                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: samples)
                self.bufferLock.unlock()

                // Calculate RMS for audio level
                let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(frames))
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
}

enum AudioError: LocalizedError {
    case formatError
    case converterError
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to create audio format"
        case .converterError: return "Failed to create audio converter"
        case .permissionDenied: return "Microphone access denied"
        }
    }
}
