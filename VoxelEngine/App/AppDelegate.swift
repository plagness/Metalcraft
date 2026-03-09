import Cocoa
import MetalKit

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var gameViewController: GameViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        print("GPU: \(device.name)")
        print("Unified Memory: \(device.hasUnifiedMemory)")
        print("Metal GPU Family Apple 7+: \(device.supportsFamily(.apple7))")

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 1280
        let windowHeight: CGFloat = 720
        let windowRect = NSRect(
            x: (screenFrame.width - windowWidth) / 2,
            y: (screenFrame.height - windowHeight) / 2,
            width: windowWidth,
            height: windowHeight
        )

        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Voxel Engine — Metal TBDR Demo"
        window.minSize = NSSize(width: 640, height: 480)

        gameViewController = GameViewController(device: device)
        window.contentViewController = gameViewController
        window.makeKeyAndOrderFront(nil)

        // Activate the app and bring to front
        NSApp.activate(ignoringOtherApps: true)

        // Lock cursor for FPS controls (delayed to ensure window is visible)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            CGAssociateMouseAndMouseCursorPosition(0)
            NSCursor.hide()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }
}
