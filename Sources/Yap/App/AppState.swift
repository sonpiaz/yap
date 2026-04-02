import SwiftUI
import Combine

enum TranscriptionMode: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case clean = "Clean"
    case smart = "Smart"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .raw: return "Verbatim — exactly what you said"
        case .clean: return "Remove fillers, fix punctuation"
        case .smart: return "Context-aware formatting (Claude)"
        }
    }

    var icon: String {
        switch self {
        case .raw: return "text.quote"
        case .clean: return "sparkles"
        case .smart: return "brain"
        }
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isModelLoaded = false
    @Published var currentMode: TranscriptionMode = .clean
    @Published var lastTranscription: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0
    @Published var error: String?

    // Stats
    @Published var totalTranscriptions: Int = 0
    @Published var totalWordsToday: Int = 0

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "transcriptionMode"),
           let mode = TranscriptionMode(rawValue: saved) {
            currentMode = mode
        }
    }

    func setMode(_ mode: TranscriptionMode) {
        currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "transcriptionMode")
    }
}
