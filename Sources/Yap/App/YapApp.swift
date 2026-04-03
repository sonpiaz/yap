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

        Window("Yap", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 380, minHeight: 500)
        }
        .defaultSize(width: 400, height: 550)

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

    /// Click dock icon → open main window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows → open main window
            for window in NSApp.windows {
                if window.title == "Yap" || window.identifier?.rawValue.contains("main") == true {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    return true
                }
            }
            // Fallback: open settings
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
