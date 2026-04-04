import AVFoundation

/// Premium audio feedback using layered harmonics for a rich, polished feel.
/// Inspired by Apple's spatial audio cues — warm, minimal, satisfying.
final class SoundFeedback {
    static let shared = SoundFeedback()

    private var player: AVAudioPlayer?

    private init() {}

    /// Warm ascending chime — "I'm listening"
    func playStartTone() {
        // C5 + E5 + G5 major chord, gentle rise
        let tones: [(frequency: Double, amplitude: Double)] = [
            (523.25, 0.5),  // C5
            (659.25, 0.35), // E5
            (783.99, 0.25), // G5
        ]
        playChord(tones: tones, duration: 0.12, volume: 0.14, fadeIn: true, pitchBend: 1.02)
    }

    /// Satisfying descending confirmation — "Got it"
    func playStopTone() {
        // G5 → C5 two-note drop with harmonics
        let tones: [(frequency: Double, amplitude: Double)] = [
            (783.99, 0.4),  // G5
            (523.25, 0.35), // C5
            (392.00, 0.2),  // G4 (sub-harmonic warmth)
        ]
        playChord(tones: tones, duration: 0.10, volume: 0.11, fadeIn: false, pitchBend: 0.98)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            let resolve: [(frequency: Double, amplitude: Double)] = [
                (523.25, 0.45), // C5
                (659.25, 0.3),  // E5
                (261.63, 0.15), // C4 (octave below for depth)
            ]
            self.playChord(tones: resolve, duration: 0.14, volume: 0.10, fadeIn: false, pitchBend: 1.0)
        }
    }

    /// Soft low tone — "Cancelled"
    func playCancelTone() {
        let tones: [(frequency: Double, amplitude: Double)] = [
            (349.23, 0.5),  // F4
            (293.66, 0.3),  // D4
        ]
        playChord(tones: tones, duration: 0.08, volume: 0.07, fadeIn: false, pitchBend: 0.96)
    }

    // MARK: - Chord Generator

    private func playChord(
        tones: [(frequency: Double, amplitude: Double)],
        duration: Double,
        volume: Float,
        fadeIn: Bool,
        pitchBend: Double
    ) {
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
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(44100).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(88200).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Generate layered sine waves with harmonics
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let progress = Double(i) / Double(frameCount)

            // Smooth envelope with cosine curves
            var envelope: Double
            let fadeOutStart = 0.5
            if fadeIn && progress < 0.25 {
                envelope = 0.5 * (1.0 - cos(.pi * progress / 0.25))
            } else if progress > fadeOutStart {
                let fadeProgress = (progress - fadeOutStart) / (1.0 - fadeOutStart)
                envelope = 0.5 * (1.0 + cos(.pi * fadeProgress))
            } else {
                envelope = 1.0
            }

            // Pitch bend over time
            let bendFactor = 1.0 + (pitchBend - 1.0) * progress

            // Sum all tones with their harmonics
            var sample = 0.0
            for tone in tones {
                let freq = tone.frequency * bendFactor
                // Fundamental
                sample += sin(2.0 * .pi * freq * t) * tone.amplitude
                // 2nd harmonic (octave, subtle)
                sample += sin(2.0 * .pi * freq * 2.0 * t) * tone.amplitude * 0.08
                // 3rd harmonic (warmth)
                sample += sin(2.0 * .pi * freq * 3.0 * t) * tone.amplitude * 0.03
            }

            sample *= envelope
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
