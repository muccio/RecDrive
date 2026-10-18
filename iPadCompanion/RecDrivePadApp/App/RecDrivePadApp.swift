import SwiftUI

/// Application entry point for RecDrive Pad (iPad Companion).
@main
struct RecDrivePadApp: App {
    var body: some Scene {
        WindowGroup {
            MirrorWorkspaceView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
