# Yap 🎤

**Voice-to-text for macOS** — Hold a key, speak, release. Text appears at your cursor.

Like Wispr Flow, but open-source and using OpenAI's best transcription model.

## Features

- **Push-to-talk** — Hold ⌘ Command (or Option/Control/Fn), speak, release
- **Vietnamese + English** — Optimized for code-switching with gpt-4o-transcribe
- **Paste anywhere** — Text inserts into any app at your cursor
- **Floating bar** — Minimal dictation indicator at top of screen
- **3 modes** — Normal, Clean (remove filler words), Email (professional rewrite)
- **Custom Dictionary** — Add names/terms for better accuracy
- **Mute music** — Auto-pause Spotify/Apple Music during dictation
- **Silence detection** — No hallucination when you don't speak
- **History** — Grouped by date, persisted across launches
- **Usage stats** — Monthly transcription count

## Install

```bash
git clone https://github.com/sonpiaz/yap.git
cd yap
./run.sh
```

Requires: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Setup

1. Get an [OpenAI API key](https://platform.openai.com/api-keys)
2. Open Yap → Settings → paste API key
3. Grant permissions: Microphone, Accessibility, Input Monitoring
4. Hold ⌘ Command and speak!

## Build DMG

```bash
./scripts/build-dmg.sh
```

## Tech Stack

- Swift + SwiftUI (native macOS)
- CGEventTap (global hotkey, no NSEvent monitor)
- AVAudioEngine → 16kHz Int16 PCM WAV
- OpenAI gpt-4o-transcribe API
- Accessibility API for text insertion

## License

MIT
