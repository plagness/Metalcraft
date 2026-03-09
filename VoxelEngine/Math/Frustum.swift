import simd

/// Axis-aligned bounding box with cached center/extents.
struct AABB {
    let min: SIMD3<Float>
    let max: SIMD3<Float>
    let center: SIMD3<Float>
    let extents: SIMD3<Float>

    init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
        self.center = (min + max) * 0.5
        self.extents = (max - min) * 0.5
    }
}

/// A plane in 3D space (normal + distance).
struct Plane {
    var normal: SIMD3<Float>
    var distance: Float

    /// Signed distance from point to plane.
    func distanceTo(_ point: SIMD3<Float>) -> Float {
        simd_dot(normal, point) + distance
    }
}

/// View frustum for culling, extracted from view-projection matrix.
struct Frustum {
    var planes: [Plane] = [] // Left, Right, Bottom, Top, Near, Far

    init() {
        planes = Array(repeating: Plane(normal: .zero, distance: 0), count: 6)
    }

    /// Extract frustum planes from a view-projection matrix.
    init(viewProjection m: simd_float4x4) {
        let row0 = SIMD4<Float>(m.columns.0.x, m.columns.1.x, m.columns.2.x, m.columns.3.x)
        let row1 = SIMD4<Float>(m.columns.0.y, m.columns.1.y, m.columns.2.y, m.columns.3.y)
        let row2 = SIMD4<Float>(m.columns.0.z, m.columns.1.z, m.columns.2.z, m.columns.3.z)
        let row3 = SIMD4<Float>(m.columns.0.w, m.columns.1.w, m.columns.2.w, m.columns.3.w)

        planes = [
            normalizePlane(row3 + row0), // Left
            normalizePlane(row3 - row0), // Right
            normalizePlane(row3 + row1), // Bottom
            normalizePlane(row3 - row1), // Top
            normalizePlane(row3 + row2), // Near
            normalizePlane(row3 - row2), // Far
        ]
    }

    /// Test if an AABB is at least partially inside the frustum.
    func containsAABB(_ aabb: AABB) -> Bool {
        let center = aabb.center
        let extents = aabb.extents

        for plane in planes {
            let r = abs(plane.normal.x) * extents.x
                  + abs(plane.normal.y) * extents.y
                  + abs(plane.normal.z) * extents.z
            let d = plane.distanceTo(center)
            if d + r < 0 { return false } // Fully outside
        }
        return true
    }

    private func normalizePlane(_ v: SIMD4<Float>) -> Plane {
        let len = simd_length(SIMD3<Float>(v.x, v.y, v.z))
        if len < 1e-6 { return Plane(normal: .zero, distance: 0) }
        let invLen = 1.0 / len
        return Plane(
            normal: SIMD3<Float>(v.x, v.y, v.z) * invLen,
            distance: v.w * invLen
        )
    }
}
