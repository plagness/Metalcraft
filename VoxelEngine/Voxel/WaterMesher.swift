import Metal
import simd

/// Mesh result for water faces in a chunk.
struct WaterMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
}

/// Generates separate meshes for water blocks (rendered with transparency).
class WaterMesher {

    private let device: MTLDevice

    /// Cache of water meshes per chunk position
    private var meshCache: [SIMD3<Int32>: WaterMesh] = [:]

    init(device: MTLDevice) {
        self.device = device
    }

    /// Get or create water mesh for a chunk.
    /// Rebuilds when the chunk has been re-meshed (isMeshed serves as version indicator).
    func getMesh(for chunk: Chunk) -> WaterMesh? {
        if let cached = meshCache[chunk.position] {
            return cached
        }

        guard let mesh = buildWaterMesh(chunk: chunk) else { return nil }
        meshCache[chunk.position] = mesh
        return mesh
    }

    /// Invalidate cache for chunks that no longer exist.
    func pruneCache(validPositions: Set<SIMD3<Int32>>) {
        for key in meshCache.keys where !validPositions.contains(key) {
            meshCache.removeValue(forKey: key)
        }
    }

    /// Invalidate a specific chunk's water mesh (e.g., when terrain re-meshed).
    func invalidate(position: SIMD3<Int32>) {
        meshCache.removeValue(forKey: position)
    }

    /// Remove cached mesh when chunk is unloaded.
    func removeMesh(for position: SIMD3<Int32>) {
        meshCache.removeValue(forKey: position)
    }

    private func buildWaterMesh(chunk: Chunk) -> WaterMesh? {
        var vertices: [VoxelVertex] = []
        var indices: [UInt32] = []

        let cs = CHUNK_SIZE
        let color = SIMD4<Float>(0.20, 0.40, 0.75, 0.5)
        let n = SIMD3<Float>(0, 1, 0)

        for ly in 0..<cs {
            for lz in 0..<cs {
                for lx in 0..<cs {
                    guard chunk.getBlock(x: lx, y: ly, z: lz) == .water else { continue }

                    // Only render top face — the water surface.
                    // No side faces: opaque terrain already closes the edges,
                    // and side faces cause massive overdraw with alpha blending.
                    let aboveIsWater: Bool
                    if ly + 1 < cs {
                        aboveIsWater = chunk.getBlock(x: lx, y: ly + 1, z: lz) == .water
                    } else {
                        aboveIsWater = false
                    }

                    guard !aboveIsWater else { continue }

                    let wp = chunk.worldPosition(localX: lx, localY: ly, localZ: lz)
                    let base = UInt32(vertices.count)
                    vertices.append(VoxelVertex(position: wp + SIMD3(0, 1, 0), normal: n, uv: SIMD2(0, 0), color: color))
                    vertices.append(VoxelVertex(position: wp + SIMD3(0, 1, 1), normal: n, uv: SIMD2(0, 1), color: color))
                    vertices.append(VoxelVertex(position: wp + SIMD3(1, 1, 1), normal: n, uv: SIMD2(1, 1), color: color))
                    vertices.append(VoxelVertex(position: wp + SIMD3(1, 1, 0), normal: n, uv: SIMD2(1, 0), color: color))
                    indices.append(contentsOf: [base, base+2, base+1, base, base+3, base+2])
                }
            }
        }

        guard !vertices.isEmpty else { return nil }

        guard let vBuf = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<VoxelVertex>.stride * vertices.count,
            options: .storageModeShared
        ),
        let iBuf = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt32>.stride * indices.count,
            options: .storageModeShared
        ) else { return nil }

        vBuf.label = "Water V (\(vertices.count))"
        iBuf.label = "Water I (\(indices.count))"

        return WaterMesh(vertexBuffer: vBuf, indexBuffer: iBuf, indexCount: indices.count)
    }
}
