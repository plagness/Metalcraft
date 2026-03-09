import Metal
import simd

/// Size of a chunk in each dimension.
let CHUNK_SIZE: Int = 16
/// Total number of blocks in a chunk.
let CHUNK_VOLUME: Int = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

/// A 16x16x16 voxel chunk with GPU-ready mesh data.
class Chunk {

    /// World-space chunk coordinate (not block coordinate).
    let position: SIMD3<Int32>

    /// Block data: 4096 UInt16 block IDs. storageModeShared for zero-copy UMA.
    let blockBuffer: MTLBuffer

    /// Pointer to block data for fast CPU access.
    let blocks: UnsafeMutablePointer<UInt16>

    /// Mesh allocation in the mega-buffer (MeshAllocator)
    var meshAllocation: MeshAllocator.Allocation?
    var vertexCount: Int = 0
    var indexCount: Int = 0

    /// State
    var isDirty: Bool = true
    var isEmpty: Bool = false
    var isMeshed: Bool = false
    var meshLODStep: Int = 1  // LOD step used when this mesh was generated

    /// World-space AABB for frustum culling — cached, not recomputed.
    let aabb: AABB

    init(position: SIMD3<Int32>, device: MTLDevice) {
        self.position = position

        let worldMin = SIMD3<Float>(
            Float(position.x) * Float(CHUNK_SIZE),
            Float(position.y) * Float(CHUNK_SIZE),
            Float(position.z) * Float(CHUNK_SIZE)
        )
        self.aabb = AABB(min: worldMin, max: worldMin + SIMD3<Float>(repeating: Float(CHUNK_SIZE)))

        let bufferSize = CHUNK_VOLUME * MemoryLayout<UInt16>.stride
        guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            fatalError("Failed to allocate chunk buffer for \(position)")
        }
        buffer.label = "Chunk (\(position.x),\(position.y),\(position.z))"
        self.blockBuffer = buffer
        self.blocks = buffer.contents().bindMemory(to: UInt16.self, capacity: CHUNK_VOLUME)

        // Initialize to air
        memset(buffer.contents(), 0, bufferSize)
    }

    // MARK: - Block Access

    /// Convert local (x,y,z) to linear index. x,y,z must be in [0, CHUNK_SIZE).
    @inline(__always)
    static func index(x: Int, y: Int, z: Int) -> Int {
        return x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE
    }

    @inline(__always)
    func getBlock(x: Int, y: Int, z: Int) -> BlockType {
        guard x >= 0, x < CHUNK_SIZE, y >= 0, y < CHUNK_SIZE, z >= 0, z < CHUNK_SIZE else {
            return .air
        }
        return BlockType(rawValue: blocks[Chunk.index(x: x, y: y, z: z)]) ?? .air
    }

    @inline(__always)
    func setBlock(x: Int, y: Int, z: Int, type: BlockType) {
        guard x >= 0, x < CHUNK_SIZE, y >= 0, y < CHUNK_SIZE, z >= 0, z < CHUNK_SIZE else { return }
        blocks[Chunk.index(x: x, y: y, z: z)] = type.rawValue
        isDirty = true
    }

    /// World-space block position from local coordinates.
    func worldPosition(localX: Int, localY: Int, localZ: Int) -> SIMD3<Float> {
        return SIMD3<Float>(
            Float(Int(position.x) * CHUNK_SIZE + localX),
            Float(Int(position.y) * CHUNK_SIZE + localY),
            Float(Int(position.z) * CHUNK_SIZE + localZ)
        )
    }

    /// Check if chunk has any non-air blocks.
    func updateIsEmpty() {
        for i in 0..<CHUNK_VOLUME {
            if blocks[i] != BlockType.air.rawValue {
                isEmpty = false
                return
            }
        }
        isEmpty = true
    }
}
