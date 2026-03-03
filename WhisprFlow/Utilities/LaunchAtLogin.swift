import Foundation
import ServiceManagement

/// Helper to manage Launch at Login functionality using SMAppService (macOS 13+)
final class LaunchAtLogin {
    
    /// Whether the app is set to launch at login
    static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status == .enabled {
                        // Already enabled
                        return
                    }
                    try SMAppService.mainApp.register()
                    logToFile("[LaunchAtLogin] Registered for launch at login")
                } else {
                    if SMAppService.mainApp.status != .enabled {
                        // Already disabled
                        return
                    }
                    try SMAppService.mainApp.unregister()
                    logToFile("[LaunchAtLogin] Unregistered from launch at login")
                }
            } catch {
                logToFile("[LaunchAtLogin] Error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Current status of the login item
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }
    
    /// Human-readable status for debugging
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return "Not registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notFound:
            return "Not found"
        @unknown default:
            return "Unknown"
        }
    }
}
