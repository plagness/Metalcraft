import Cocoa
import simd

/// Manages keyboard and mouse input state for FPS camera control.
class InputManager {

    // MARK: - Key Codes (macOS virtual key codes)
    static let keyW: UInt16     = 13
    static let keyA: UInt16     = 0
    static let keyS: UInt16     = 1
    static let keyD: UInt16     = 2
    static let keyQ: UInt16     = 12
    static let keyE: UInt16     = 14
    static let keySpace: UInt16 = 49
    static let keyShift: UInt16 = 56
    static let keyEscape: UInt16 = 53
    static let keyF1: UInt16    = 122
    static let keyF2: UInt16    = 120
    static let keyF3: UInt16    = 99
    static let keyTab: UInt16   = 48

    // MARK: - State
    private var keysPressed: Set<UInt16> = []
    private var mouseDelta: SIMD2<Float> = .zero
    private var mouseButtons: Set<Int> = []
    private var scrollDelta: Float = 0

    var mouseSensitivity: Float = 0.002
    var cursorLocked: Bool = true

    // MARK: - Key Events

    func keyDown(keyCode: UInt16) {
        keysPressed.insert(keyCode)

        if keyCode == Self.keyEscape {
            toggleCursorLock()
        }
    }

    func keyUp(keyCode: UInt16) {
        keysPressed.remove(keyCode)
    }

    func isKeyPressed(_ keyCode: UInt16) -> Bool {
        keysPressed.contains(keyCode)
    }

    // MARK: - Mouse Events

    func mouseMoved(deltaX: Float, deltaY: Float) {
        guard cursorLocked else { return }
        mouseDelta.x += deltaX
        mouseDelta.y += deltaY
    }

    func mouseDown(button: Int) {
        mouseButtons.insert(button)
    }

    func mouseUp(button: Int) {
        mouseButtons.remove(button)
    }

    func scrollWheel(deltaY: Float) {
        scrollDelta += deltaY
    }

    func isMouseButtonPressed(_ button: Int) -> Bool {
        mouseButtons.contains(button)
    }

    // MARK: - Per-Frame Queries

    /// Returns and resets accumulated mouse delta for this frame.
    func consumeMouseDelta() -> SIMD2<Float> {
        let delta = mouseDelta * mouseSensitivity
        mouseDelta = .zero
        return delta
    }

    /// Returns and resets scroll delta.
    func consumeScrollDelta() -> Float {
        let delta = scrollDelta
        scrollDelta = 0
        return delta
    }

    /// Returns movement direction based on WASD+Space+Shift in camera local space.
    /// x = right, y = up, z = forward (negative Z in Metal's coordinate system)
    func movementInput() -> SIMD3<Float> {
        var move = SIMD3<Float>.zero

        if isKeyPressed(Self.keyW) { move.z -= 1 } // Forward
        if isKeyPressed(Self.keyS) { move.z += 1 } // Back
        if isKeyPressed(Self.keyA) { move.x -= 1 } // Left
        if isKeyPressed(Self.keyD) { move.x += 1 } // Right
        if isKeyPressed(Self.keySpace) { move.y += 1 }  // Up
        if isKeyPressed(Self.keyShift) { move.y -= 1 }  // Down

        let lengthSq = simd_length_squared(move)
        if lengthSq > 0 {
            move = simd_normalize(move)
        }
        return move
    }

    // MARK: - Cursor Lock

    private func toggleCursorLock() {
        cursorLocked.toggle()
        if cursorLocked {
            CGAssociateMouseAndMouseCursorPosition(0)
            NSCursor.hide()
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
        }
    }
}
