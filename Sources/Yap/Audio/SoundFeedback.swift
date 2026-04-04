import AVFoundation

/// Premium audio feedback using pre-rendered WAV files.
/// Generated with studio DSP: layered synthesis, ADSR envelopes,
/// biquad filters, soft saturation, convolution reverb.
///
/// Sound files: Resources/Sounds/*.wav (48kHz 16-bit mono)
final class SoundFeedback {
    static let shared = SoundFeedback()

    private var player: AVAudioPlayer?

    private init() {}

    /// Warm bass bloom — "I'm listening"
    func playStartTone() {
        play("start")
    }

    /// Deep resonant confirmation — "Got it"
    func playStopTone() {
        play("stop")
    }

    /// Subtle muted thud — "Cancelled"
    func playCancelTone() {
        play("cancel")
    }

    /// Gentle warning — "Something went wrong"
    func playErrorTone() {
        play("error")
    }

    // MARK: - Playback

    private func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") else {
            NSLog("[Yap] Sound file not found: %@.wav", name)
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 0.5
            player?.play()
        } catch {
            NSLog("[Yap] Sound playback error: %@", error.localizedDescription)
        }
    }
}
