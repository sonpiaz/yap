<h1 align="center">Yap</h1>

<p align="center">
  Push-to-talk dictation for macOS. Hold a hotkey, speak, text appears.
</p>

<p align="center">
  <a href="https://github.com/sonpiaz/yap/blob/main/LICENSE"><img src="https://img.shields.io/github/license/sonpiaz/yap" alt="License" /></a>
  <a href="https://github.com/sonpiaz/yap/stargazers"><img src="https://img.shields.io/github/stars/sonpiaz/yap" alt="Stars" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9" />
</p>

---

## Features

- **Push-to-talk** — Hold `⌥Space` to record, or press once to toggle
- **Auto-paste** — Transcribed text is pasted directly into the active app
- **Multi-provider STT** — Groq (Whisper v3 Turbo), OpenAI (Whisper-1), Deepgram (Nova-3)
- **Vietnamese + English** — Auto-detect or lock to a specific language
- **Recording controls** — Mic selector, noise suppression, live input meter, mic test
- **Transcription history** — Copy any previous transcription with one click
- **Menu bar app** — Always ready, no dock icon

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

## Requirements

- macOS 14.0 (Sonoma) or later
- API key from one of: Groq, OpenAI, or Deepgram
- Accessibility permission (for auto-paste)
- Microphone permission

## Privacy

Yap sends audio data **only** to the STT provider you choose for transcription. No audio is stored locally or sent anywhere else. API keys are stored in UserDefaults on your Mac.

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
```

## Tech Stack

| Technology | Purpose |
|-----------|---------|
| [Swift 5.9](https://swift.org/) | Language |
| SwiftUI | UI framework |
| AVFoundation | Audio capture |
| Cloud STT APIs | Groq, OpenAI, Deepgram |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Project generation |

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Related

- [Kapt](https://github.com/sonpiaz/kapt) — macOS screenshot tool with annotation & OCR
- [hidrix-tools](https://github.com/sonpiaz/hidrix-tools) — MCP server for web & social search
- [affiliate-skills](https://github.com/Affitor/affiliate-skills) — 45 AI agent skills
- [content-pipeline](https://github.com/Affitor/content-pipeline) — AI-powered LinkedIn content generation

## License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">Built by <a href="https://github.com/sonpiaz">Son Piaz</a></p>
