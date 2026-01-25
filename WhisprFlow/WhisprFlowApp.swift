import SwiftUI

/// Main entry point for WhisprFlow.
/// The app uses AppDelegate for AppKit integration (pill window, hotkeys).
@main
struct WhisprFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We use a Settings scene for future settings window
        // The main UI is the pill window managed by AppDelegate
        Settings {
            EmptyView()
        }
    }
}
