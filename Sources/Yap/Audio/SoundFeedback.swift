import AVFoundation

/// Minimal, elegant audio feedback — inspired by Apple's design philosophy.
/// Short sine-wave tones: gentle, non-intrusive, satisfying.
final class SoundFeedback {
    static let shared = SoundFeedback()

    private var player: AVAudioPlayer?

    private init() {}

    /// Soft ascending tone — "I'm listening" (like a gentle inhale)
    func playStartTone() {
        playTone(frequency: 880, duration: 0.08, volume: 0.15, fadeIn: true)
    }

    /// Soft descending double-tap — "Got it" (like a gentle exhale)  
    func playStopTone() {
        playTone(frequency: 660, duration: 0.06, volume: 0.12, fadeIn: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.playTone(frequency: 880, duration: 0.06, volume: 0.10, fadeIn: false)
        }
    }

    /// Single soft low tone — "Cancelled"
    func playCancelTone() {
        playTone(frequency: 440, duration: 0.06, volume: 0.08, fadeIn: false)
    }

    // MARK: - Tone Generator

    private func playTone(frequency: Double, duration: Double, volume: Float, fadeIn: Bool) {
        let sampleRate: Double = 44100
        let frameCount = Int(sampleRate * duration)

        var data = Data()

        // WAV header
        let dataSize = UInt32(frameCount * 2)
        let fileSize = dataSize + 36
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(44100).littleEndian) { Array($0) }) // sample rate
        data.append(contentsOf: withUnsafeBytes(of: UInt32(88200).littleEndian) { Array($0) }) // byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })   // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })  // bits per sample
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Generate sine wave with fade envelope
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let progress = Double(i) / Double(frameCount)

            // Smooth envelope: fade in + fade out
            var envelope: Double
            let fadeOutStart = 0.6
            if fadeIn && progress < 0.3 {
                envelope = progress / 0.3  // fade in
            } else if progress > fadeOutStart {
                envelope = (1.0 - progress) / (1.0 - fadeOutStart)  // fade out
            } else {
                envelope = 1.0
            }

            let sample = sin(2.0 * .pi * frequency * t) * envelope
            let int16 = Int16(clamping: Int(sample * Double(Int16.max)))
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        do {
            player = try AVAudioPlayer(data: data)
            player?.volume = volume
            player?.play()
        } catch {
            // Silent fail — sound is non-critical
        }
    }
}
