import Foundation
import simd

/// First-person camera with FPS-style controls.
class CameraSystem {

    // MARK: - Transform
    var position: SIMD3<Float> = SIMD3<Float>(0, 20, 30)
    var yaw: Float = 0         // Rotation around Y axis (radians)
    var pitch: Float = 0       // Rotation around X axis (radians)

    // MARK: - Projection
    var fov: Float = 70.0      // Vertical FOV in degrees
    var nearPlane: Float = 0.1
    var farPlane: Float = 2500.0  // 128 chunks * 16 = 2048 blocks, +20% safety
    var aspectRatio: Float = 16.0 / 9.0

    // MARK: - Movement
    var moveSpeed: Float = 30.0
    var sprintMultiplier: Float = 5.0

    // MARK: - Previous frame (for motion vectors)
    private var previousViewProjection: simd_float4x4 = matrix_identity_float4x4

    // MARK: - Computed Matrices

    var forward: SIMD3<Float> {
        SIMD3<Float>(
            -sin(yaw) * cos(pitch),
            sin(pitch),
            -cos(yaw) * cos(pitch)
        )
    }

    var right: SIMD3<Float> {
        SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    }

    var up: SIMD3<Float> {
        simd_cross(right, forward)
    }

    var viewMatrix: simd_float4x4 {
        let target = position + forward
        return CameraSystem.lookAt(eye: position, target: target, up: SIMD3<Float>(0, 1, 0))
    }

    var projectionMatrix: simd_float4x4 {
        CameraSystem.perspective(fovYDegrees: fov, aspect: aspectRatio, near: nearPlane, far: farPlane)
    }

    var viewProjectionMatrix: simd_float4x4 {
        projectionMatrix * viewMatrix
    }

    // MARK: - Update

    func update(input: InputManager, deltaTime: Float) {
        previousViewProjection = viewProjectionMatrix

        // Mouse look
        let mouseDelta = input.consumeMouseDelta()
        yaw -= mouseDelta.x
        pitch -= mouseDelta.y
        pitch = clamp(pitch, min: -.pi / 2.0 + 0.01, max: .pi / 2.0 - 0.01)

        // Movement
        let movement = input.movementInput()
        let isSprinting = input.isKeyPressed(InputManager.keyTab)
        let speed = moveSpeed * (isSprinting ? sprintMultiplier : 1.0) * deltaTime

        position += right * movement.x * speed
        position += SIMD3<Float>(0, 1, 0) * movement.y * speed
        position += forward * (-movement.z) * speed

        // Scroll to change speed
        let scroll = input.consumeScrollDelta()
        moveSpeed = max(1.0, moveSpeed + scroll * 2.0)
    }

    func buildUniforms(screenWidth: Float, screenHeight: Float, time: Float, frameIndex: UInt32) -> FrameUniforms {
        aspectRatio = screenWidth / screenHeight

        let view = viewMatrix
        let proj = projectionMatrix
        let vp = proj * view

        var uniforms = FrameUniforms()
        uniforms.viewMatrix = view
        uniforms.projectionMatrix = proj
        uniforms.viewProjectionMatrix = vp
        uniforms.inverseViewMatrix = view.inverse
        uniforms.inverseProjectionMatrix = proj.inverse
        uniforms.previousViewProjectionMatrix = previousViewProjection
        uniforms.viewProjectionMatrixJittered = vp // No jitter in Phase 1
        uniforms.cameraPosition = position
        uniforms.time = time
        uniforms.jitterOffset = SIMD2<Float>(0, 0)
        uniforms.screenSize = SIMD2<Float>(screenWidth, screenHeight)
        uniforms.frameIndex = frameIndex
        uniforms.lightCount = 0
        uniforms.nearPlane = nearPlane
        uniforms.farPlane = farPlane

        return uniforms
    }

    // MARK: - Matrix Math

    static func perspective(fovYDegrees: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let fovY = fovYDegrees * .pi / 180.0
        let sy = 1.0 / tan(fovY * 0.5)
        let sx = sy / aspect
        let zRange = far - near

        return simd_float4x4(columns: (
            SIMD4<Float>(sx,  0,   0,                           0),
            SIMD4<Float>(0,   sy,  0,                           0),
            SIMD4<Float>(0,   0,   -(far + near) / zRange,     -1),
            SIMD4<Float>(0,   0,   -2.0 * far * near / zRange,  0)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(target - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)

        return simd_float4x4(columns: (
            SIMD4<Float>(s.x,  u.x, -f.x, 0),
            SIMD4<Float>(s.y,  u.y, -f.y, 0),
            SIMD4<Float>(s.z,  u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }

    private func clamp(_ value: Float, min minVal: Float, max maxVal: Float) -> Float {
        return Swift.min(Swift.max(value, minVal), maxVal)
    }
}
