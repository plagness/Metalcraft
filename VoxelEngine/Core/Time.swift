import Foundation
import QuartzCore

/// Tracks frame timing, delta time, and FPS.
struct TimeState {
    var deltaTime: Float = 1.0 / 60.0
    var totalTime: Float = 0
    var frameCount: UInt64 = 0
    var fps: Float = 60
    var smoothFPS: Float = 60

    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var fpsAccumulator: Float = 0
    private var fpsFrameCount: Int = 0
    private var fpsUpdateInterval: Float = 0.5

    mutating func update() {
        let now = CACurrentMediaTime()
        deltaTime = Float(now - lastTimestamp)
        lastTimestamp = now

        // Clamp delta time to prevent spiral of death
        deltaTime = min(deltaTime, 1.0 / 15.0)

        totalTime += deltaTime
        frameCount += 1

        // FPS calculation (averaged over 0.5s)
        fpsAccumulator += deltaTime
        fpsFrameCount += 1

        if fpsAccumulator >= fpsUpdateInterval {
            fps = Float(fpsFrameCount) / fpsAccumulator
            smoothFPS = smoothFPS * 0.9 + fps * 0.1
            fpsAccumulator = 0
            fpsFrameCount = 0
        }
    }
}
