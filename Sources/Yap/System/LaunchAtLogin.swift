import ServiceManagement

enum LaunchAtLogin {
    static func set(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                NSLog("[Yap] Launch at login enabled")
            } else {
                try SMAppService.mainApp.unregister()
                NSLog("[Yap] Launch at login disabled")
            }
        } catch {
            NSLog("[Yap] Launch at login error: %@", error.localizedDescription)
        }
    }
}
