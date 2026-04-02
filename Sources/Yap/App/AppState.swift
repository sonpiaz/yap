import SwiftUI

struct Transcription: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var error: String?
    @Published var transcriptions: [Transcription] = []

    private init() {}

    func addTranscription(_ text: String) {
        let entry = Transcription(text: text, timestamp: Date())
        transcriptions.insert(entry, at: 0)

        // Auto-paste or copy to clipboard
        TextInserter.insert(text)
    }
}
