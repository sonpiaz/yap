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
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Yap] App launched")
        NSApplication.shared.setActivationPolicy(.regular)
        PipelineController.shared.setup()
    }

    /// Click dock icon → open main window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showMainWindow() {
        if let window = mainWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = MainView()
            .environmentObject(AppState.shared)
            .frame(minWidth: 500, minHeight: 450)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Yap"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }
}
