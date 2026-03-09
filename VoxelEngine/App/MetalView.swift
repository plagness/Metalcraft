import Cocoa
import MetalKit

/// Custom MTKView that captures keyboard and mouse input for FPS camera.
class MetalView: MTKView {

    weak var inputManager: InputManager?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        inputManager?.keyDown(keyCode: event.keyCode)
    }

    override func keyUp(with event: NSEvent) {
        inputManager?.keyUp(keyCode: event.keyCode)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        inputManager?.mouseMoved(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
    }

    override func mouseDragged(with event: NSEvent) {
        inputManager?.mouseMoved(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
    }

    override func rightMouseDragged(with event: NSEvent) {
        inputManager?.mouseMoved(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
    }

    override func mouseDown(with event: NSEvent) {
        inputManager?.mouseDown(button: 0)
    }

    override func mouseUp(with event: NSEvent) {
        inputManager?.mouseUp(button: 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        inputManager?.mouseDown(button: 1)
    }

    override func rightMouseUp(with event: NSEvent) {
        inputManager?.mouseUp(button: 1)
    }

    override func scrollWheel(with event: NSEvent) {
        inputManager?.scrollWheel(deltaY: Float(event.scrollingDeltaY))
    }

    // Prevent system beep on key press
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        return true
    }
}
