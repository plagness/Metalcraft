import simd

typealias Float4x4 = simd_float4x4

extension Float4x4 {
    static func perspective(fovY: Float, aspect: Float, nearZ: Float, farZ: Float) -> Float4x4 {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange

        return Float4x4(
            SIMD4(xScale, 0, 0, 0),
            SIMD4(0, yScale, 0, 0),
            SIMD4(0, 0, zScale, -1),
            SIMD4(0, 0, wzScale, 0)
        )
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> Float4x4 {
        let zAxis = simd_normalize(eye - center)
        let xAxis = simd_normalize(simd_cross(up, zAxis))
        let yAxis = simd_cross(zAxis, xAxis)
        let translation = SIMD3(-simd_dot(xAxis, eye), -simd_dot(yAxis, eye), -simd_dot(zAxis, eye))

        return Float4x4(
            SIMD4(xAxis.x, yAxis.x, zAxis.x, 0),
            SIMD4(xAxis.y, yAxis.y, zAxis.y, 0),
            SIMD4(xAxis.z, yAxis.z, zAxis.z, 0),
            SIMD4(translation.x, translation.y, translation.z, 1)
        )
    }
}
