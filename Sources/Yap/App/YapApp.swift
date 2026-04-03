import SwiftUI

@main
struct YapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
                .frame(width: 360, height: 400)
        } label: {
            Label("Yap", systemImage: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Yap] App launched")
        NSApplication.shared.setActivationPolicy(.regular)
        PipelineController.shared.setup()
    }

    /// Click dock icon → open Settings directly
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
