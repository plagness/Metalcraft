import MetalcraftUI
import SwiftUI

@main
struct MetalcraftApp: App {
    var body: some Scene {
        WindowGroup("Metalcraft") {
            GameDashboardScreen()
                .frame(minWidth: 1280, minHeight: 860)
        }
        .defaultSize(width: 1480, height: 940)
        .windowToolbarStyle(.unifiedCompact)
    }
}
