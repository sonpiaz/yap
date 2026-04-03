# Yap

Push-to-talk dictation for macOS. Hold a hotkey, speak, text appears.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)

Yap is a menu bar app that transcribes speech to text in real-time using cloud STT providers. Hold a hotkey, speak, and the transcription is pasted directly into any app. Supports Vietnamese and English with auto-detection.

## Install

### Homebrew (recommended)

```bash
brew install --cask sonpiaz/tap/yap
```

### Build from source

```bash
git clone https://github.com/sonpiaz/yap.git
cd yap
brew install xcodegen    # if not installed
make run
```

## Quick Start

1. Open Yap from menu bar
2. Go to Settings → add your API key ([Groq](https://console.groq.com), [OpenAI](https://platform.openai.com), or [Deepgram](https://console.deepgram.com))
3. Choose STT provider and language
4. Hold `⌥Space` and speak

## Features

| Feature | Description |
|---------|-------------|
| **Push-to-talk** | Hold `⌥Space` to record, or press once to toggle |
| **Auto-paste** | Transcribed text is pasted directly into the active app |
| **Multi-provider STT** | Groq (Whisper v3 Turbo), OpenAI (Whisper-1), Deepgram (Nova-3) |
| **Vietnamese + English** | Auto-detect or lock to a specific language |
| **Recording controls** | Mic selector, noise suppression, live input meter, mic test |
| **Transcription history** | Copy any previous transcription with one click |
| **Permission status** | Check mic and accessibility access from Settings |
| **Menu bar app** | Always ready, no dock icon |

## Requirements

- macOS 14.0 (Sonoma) or later
- API key from one of: Groq, OpenAI, or Deepgram
- Accessibility permission (for auto-paste)
- Microphone permission

## Permissions

Yap requests two permissions at runtime:

1. **Microphone** — Required to capture audio for transcription
2. **Accessibility** — Required to paste transcribed text into the active app

Grant them in System Settings → Privacy & Security.

## Development

```bash
make generate    # Generate Xcode project
make build       # Build via xcodebuild
make run         # Build and run
make clean       # Clean build artifacts
```

## Project Structure

```
Sources/Yap/
├── YapApp.swift              — App entry, menu bar
├── Audio/                    — AVFoundation audio capture
├── Transcription/            — STT provider integration (Groq/OpenAI/Deepgram)
├── Input/                    — Hotkey management, text insertion
├── Settings/                 — Settings UI
└── History/                  — Transcription history

Resources/
├── Info.plist
├── Yap.entitlements
└── Assets.xcassets
```

## Tech Stack

- **Language:** Swift 5.9 / SwiftUI
- **Audio:** AVFoundation
- **STT:** Cloud APIs (Groq, OpenAI, Deepgram)
- **Build:** XcodeGen + xcodebuild

## Privacy

Yap sends audio data **only** to the STT provider you choose (Groq, OpenAI, or Deepgram) for transcription. No audio is stored locally or sent anywhere else. API keys are stored in UserDefaults on your Mac.

## Contributing

Pull requests welcome. For major changes, please open an issue first.

1. Fork the repo
2. Create your branch (`git checkout -b feat/amazing-feature`)
3. Commit (`git commit -m 'feat: add amazing feature'`)
4. Push (`git push origin feat/amazing-feature`)
5. Open a Pull Request

## Related

- [Kapt](https://github.com/sonpiaz/kapt) — macOS screenshot tool with annotation & OCR
- [hidrix-tools](https://github.com/sonpiaz/hidrix-tools) — MCP server for web & social search
- [affiliate-skills](https://github.com/Affitor/affiliate-skills) — 45 AI agent skills
- [evox](https://github.com/sonpiaz/evox) — Multi-agent orchestration system

## License

[MIT](LICENSE) — Son Piaz
