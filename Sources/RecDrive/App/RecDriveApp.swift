import SwiftUI
import AppKit

/// Application entry point configuring RecDrive as a pure macOS menu bar application (LSUIElement).
@main
struct RecDriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

/// AppKit Application Delegate configuring the menu bar status item and accessory policy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce accessory policy: menu bar only, no dock icon, no Command+Tab item
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize StatusItem and attach MenuBarView popover
        let menuBarView = MenuBarView()
        StatusItemController.shared.setupStatusItem(contentView: AnyView(menuBarView))
        
        // Initialize Global HotKey Manager for Screen Annotation
        HotKeyManager.shared.registerFromPreferences()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar apps stay running even if settings window closes
        return false
    }
}
