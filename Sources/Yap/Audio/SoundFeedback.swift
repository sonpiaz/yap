import AVFoundation

/// Premium audio feedback — warm, deep, luxurious.
/// Inspired by high-end product sounds: gentle bass resonance, not shrill chimes.
/// Think: the satisfying click of a Leica shutter, not a phone notification.
final class SoundFeedback {
    static let shared = SoundFeedback()

    private var player: AVAudioPlayer?

    private init() {}

    /// Warm bass bloom — a gentle "thum" that says "I'm listening"
    /// Deep C3 with soft overtones, like a felt-dampened piano key
    func playStartTone() {
        let sampleRate: Double = 44100
        let duration: Double = 0.22
        let frameCount = Int(sampleRate * duration)

        var samples = [Double](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let progress = Double(i) / Double(frameCount)

            // Envelope: quick attack (15ms), long gentle decay
            let attack: Double = 0.015
            let envelope: Double
            if progress < attack / duration {
                // Smooth attack with sine curve
                envelope = sin(.pi * 0.5 * (t / attack))
            } else {
                // Exponential decay — natural, organic
                let decayT = (t - attack) / (duration - attack)
                envelope = exp(-3.5 * decayT) * (0.5 * (1.0 + cos(.pi * decayT)))
            }

            // Layer 1: Deep fundamental — C3 (130.81 Hz) — the body
            let fundamental = sin(2.0 * .pi * 130.81 * t) * 0.45

            // Layer 2: Warm fifth — G3 (196.00 Hz) — adds richness
            let fifth = sin(2.0 * .pi * 196.00 * t) * 0.20

            // Layer 3: Sub-bass — C2 (65.41 Hz) — felt more than heard
            let sub = sin(2.0 * .pi * 65.41 * t) * 0.25

            // Layer 4: Gentle overtone — E4 (329.63 Hz) — sparkle on top
            let overtone = sin(2.0 * .pi * 329.63 * t) * 0.08 * exp(-6.0 * progress)

            // Layer 5: Soft noise texture for "air" — very subtle
            let noise = (Double.random(in: -1...1)) * 0.012 * exp(-8.0 * progress)

            samples[i] = (fundamental + fifth + sub + overtone + noise) * envelope
        }

        play(samples: samples, sampleRate: sampleRate, volume: 0.18)
    }

    /// Deep resonant confirmation — "Got it"
    /// Two-stage: soft bass drop → warm resolve. Like a velvet curtain closing.
    func playStopTone() {
        let sampleRate: Double = 44100
        let duration: Double = 0.30
        let frameCount = Int(sampleRate * duration)

        var samples = [Double](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let progress = Double(i) / Double(frameCount)

            // Two-phase envelope
            let phase1End: Double = 0.12 // first note
            let envelope: Double
            if t < phase1End {
                let p = t / phase1End
                let att = min(1.0, p / 0.08) // 8ms attack
                envelope = att * (0.5 * (1.0 + cos(.pi * p * 0.7)))
            } else {
                let p = (t - phase1End) / (duration - phase1End)
                let att = min(1.0, p / 0.05)
                envelope = att * 0.85 * exp(-3.0 * p) * (0.5 * (1.0 + cos(.pi * p)))
            }

            // Phase 1: G3 drop
            let freq1: Double = t < phase1End ? 196.00 : 0
            // Phase 2: Resolve to C3 — warm landing
            let freq2: Double = t >= phase1End ? 130.81 : 0

            // Pitch: gentle downward slide for organic feel
            let pitchSlide = 1.0 - 0.015 * progress

            var sample = 0.0

            if freq1 > 0 {
                sample += sin(2.0 * .pi * freq1 * pitchSlide * t) * 0.40
                sample += sin(2.0 * .pi * freq1 * 0.5 * t) * 0.20 // sub octave
                sample += sin(2.0 * .pi * freq1 * 2.0 * t) * 0.06 * exp(-5.0 * t / phase1End) // overtone
            }

            if freq2 > 0 {
                let t2 = t - phase1End
                sample += sin(2.0 * .pi * freq2 * pitchSlide * t2) * 0.40
                sample += sin(2.0 * .pi * 65.41 * t2) * 0.22 // C2 sub-bass
                sample += sin(2.0 * .pi * freq2 * 3.0 * t2) * 0.04 * exp(-8.0 * t2) // 3rd harmonic sparkle
            }

            samples[i] = sample * envelope
        }

        play(samples: samples, sampleRate: sampleRate, volume: 0.15)
    }

    /// Subtle muted thud — "Cancelled"
    /// Barely there, like a soft door close
    func playCancelTone() {
        let sampleRate: Double = 44100
        let duration: Double = 0.10
        let frameCount = Int(sampleRate * duration)

        var samples = [Double](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let progress = Double(i) / Double(frameCount)

            let envelope = exp(-8.0 * progress)

            // Just a low thud — A2 (110 Hz)
            let sample = sin(2.0 * .pi * 110.0 * t) * 0.35 +
                          sin(2.0 * .pi * 55.0 * t) * 0.20 +  // sub
                          Double.random(in: -1...1) * 0.03 * exp(-15.0 * progress) // click texture

            samples[i] = sample * envelope
        }

        play(samples: samples, sampleRate: sampleRate, volume: 0.10)
    }

    // MARK: - Audio Engine

    private func play(samples: [Double], sampleRate: Double, volume: Float) {
        let frameCount = samples.count

        var data = Data()

        // WAV header — 16-bit mono PCM
        let dataSize = UInt32(frameCount * 2)
        let fileSize = dataSize + 36
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(sampleRate)).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(sampleRate) * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })  // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Convert to int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Double(Int16.max))
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
