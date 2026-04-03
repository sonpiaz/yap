import SwiftUI

struct Transcription: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var audioLevel: Float = 0
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: String?
    @Published var transcriptions: [Transcription] = []
    @Published var showOverlay = false

    private init() {}

    var menuBarIcon: String {
        if isRecording { return "record.circle.fill" }
        if isTranscribing { return "ellipsis.circle" }
        return "waveform.circle"
    }

    func addTranscription(_ text: String) {
        transcriptions.insert(Transcription(text: text, timestamp: Date()), at: 0)
    }
}
