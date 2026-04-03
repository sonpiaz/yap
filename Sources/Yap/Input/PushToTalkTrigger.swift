import SwiftUI
import AppKit

enum TriggerModifier: String, CaseIterable, Codable, Identifiable {
    case command
    case option
    case control
    case shift
    case function

    var id: String { rawValue }

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        case .function: return .function
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        case .function: return "fn"
        }
    }

    var displayName: String {
        switch self {
        case .command: return "Command"
        case .option: return "Option"
        case .control: return "Control"
        case .shift: return "Shift"
        case .function: return "Fn"
        }
    }
}

struct PushToTalkTrigger: Codable, Equatable {
    enum Kind: String, Codable {
        case modifier
        case combo
    }

    let kind: Kind
    let modifier: TriggerModifier?
    let keyCode: UInt16?
    let key: String?
    let modifiers: [TriggerModifier]

    static func modifier(_ modifier: TriggerModifier) -> Self {
        .init(kind: .modifier, modifier: modifier, keyCode: nil, key: nil, modifiers: [])
    }

    static func combo(keyCode: UInt16, key: String, modifiers: [TriggerModifier]) -> Self {
        .init(kind: .combo, modifier: nil, keyCode: keyCode, key: key, modifiers: modifiers)
    }

    var displayText: String {
        switch kind {
        case .modifier:
            return modifier?.symbol ?? "—"
        case .combo:
            let parts = modifiers.map(\.symbol) + [key ?? "?"]
            return parts.joined(separator: " ")
        }
    }

    var helpText: String {
        switch kind {
        case .modifier:
            return "Modifier only"
        case .combo:
            return "Key combination"
        }
    }

    static let defaultValue = PushToTalkTrigger.modifier(.option)
}

extension PushToTalkTrigger {
    static func loadFromDefaults() -> PushToTalkTrigger {
        guard
            let raw = UserDefaults.standard.string(forKey: "pushToTalkTriggerData"),
            let data = raw.data(using: .utf8),
            let trigger = try? JSONDecoder().decode(PushToTalkTrigger.self, from: data)
        else {
            return .defaultValue
        }

        return trigger
    }

    static func saveToDefaults(_ trigger: PushToTalkTrigger?) {
        if let trigger,
           let data = try? JSONEncoder().encode(trigger),
           let raw = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(raw, forKey: "pushToTalkTriggerData")
        } else {
            UserDefaults.standard.removeObject(forKey: "pushToTalkTriggerData")
        }
    }
}

struct TriggerRecorderField: View {
    @Binding var trigger: PushToTalkTrigger
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trigger.displayText)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.medium)
                Text(isRecording ? "Press any key or modifier" : trigger.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isRecording ? "Recording…" : "Change") {
                isRecording.toggle()
            }
            .buttonStyle(.bordered)

            if isRecording {
                Button("Cancel") {
                    isRecording = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.35))
        )
        .background(
            TriggerCaptureRepresentable(isRecording: $isRecording) { newTrigger in
                trigger = newTrigger
                PushToTalkTrigger.saveToDefaults(newTrigger)
            }
        )
    }
}

private struct TriggerCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (PushToTalkTrigger) -> Void

    func makeNSView(context: Context) -> TriggerCaptureView {
        let view = TriggerCaptureView()
        view.onCapture = { trigger in
            onCapture(trigger)
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: TriggerCaptureView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording, nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class TriggerCaptureView: NSView {
    var onCapture: ((PushToTalkTrigger) -> Void)?
    var onCancel: (() -> Void)?
    var isRecording = false {
        didSet {
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isRecording {
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            onCancel?()
            return
        }

        let modifiers = Self.modifiers(from: event.modifierFlags)
        let key = Self.displayKey(for: event)
        onCapture?(.combo(keyCode: event.keyCode, key: key, modifiers: modifiers))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let modifiers = Self.modifiers(from: event.modifierFlags)
        guard modifiers.count == 1, let modifier = modifiers.first else { return }
        onCapture?(.modifier(modifier))
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> [TriggerModifier] {
        let clean = flags.intersection(.deviceIndependentFlagsMask)
        return TriggerModifier.allCases.filter { clean.contains($0.eventFlag) }
    }

    private static func displayKey(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Esc"
        default:
            let text = event.charactersIgnoringModifiers?.uppercased() ?? "Key"
            return text == " " ? "Space" : text
        }
    }
}
