import SwiftUI

struct Transcription: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
    }
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

    private init() {
        loadHistory()
    }

    var menuBarIcon: String {
        if isRecording { return "record.circle.fill" }
        if isTranscribing { return "ellipsis.circle" }
        return "waveform.circle"
    }

    func addTranscription(_ text: String) {
        transcriptions.insert(Transcription(text: text), at: 0)
        if transcriptions.count > 200 { transcriptions = Array(transcriptions.prefix(200)) }
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(transcriptions) {
            UserDefaults.standard.set(data, forKey: "transcriptionHistory")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "transcriptionHistory"),
              let saved = try? JSONDecoder().decode([Transcription].self, from: data) else { return }
        transcriptions = saved
    }
}
