import Metal
import simd

/// Sub-allocator for a mega vertex buffer and a mega index buffer.
/// All chunk meshes live in a single VBO + single IBO — one bind per frame instead of 4500.
///
/// Strategy: bump pointer with free list (best-fit). O(N) free list scan is fine
/// because allocations happen at ~24/frame (mesh throughput), not per-frame.
///
/// Memory budget:
///   Vertex buffer: 128 MB (storageModeShared, Apple Silicon UMA)
///   Index buffer:  64 MB
class MeshAllocator {

    /// Represents a region within the mega-buffers.
    struct Allocation {
        let vertexOffset: Int    // byte offset in mega vertex buffer
        let indexOffset: Int     // byte offset in mega index buffer
        let vertexBytes: Int     // size of vertex data
        let indexBytes: Int      // size of index data
        let vertexCount: Int
        let indexCount: Int
    }

    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer

    private let vertexCapacity: Int   // total bytes in vertex buffer
    private let indexCapacity: Int    // total bytes in index buffer

    // Bump pointers (current high-water mark)
    private var vertexBumpOffset: Int = 0
    private var indexBumpOffset: Int = 0

    // Free lists: sorted by offset for coalescing
    private var vertexFreeList: [(offset: Int, size: Int)] = []
    private var indexFreeList: [(offset: Int, size: Int)] = []

    // Alignment: 16 bytes (matches PackedVoxelVertex stride)
    private let alignment: Int = 16

    // Stats
    private(set) var vertexBytesUsed: Int = 0
    private(set) var indexBytesUsed: Int = 0
    private(set) var allocationCount: Int = 0

    init(device: MTLDevice, vertexMB: Int = 128, indexMB: Int = 64) {
        vertexCapacity = vertexMB * 1024 * 1024
        indexCapacity = indexMB * 1024 * 1024

        guard let vBuf = device.makeBuffer(length: vertexCapacity, options: .storageModeShared) else {
            fatalError("MeshAllocator: failed to allocate \(vertexMB)MB vertex buffer")
        }
        vBuf.label = "MegaVertexBuffer"
        vertexBuffer = vBuf

        guard let iBuf = device.makeBuffer(length: indexCapacity, options: .storageModeShared) else {
            fatalError("MeshAllocator: failed to allocate \(indexMB)MB index buffer")
        }
        iBuf.label = "MegaIndexBuffer"
        indexBuffer = iBuf
    }

    // MARK: - Allocate

    /// Allocate space for vertex and index data. Returns nil if out of space.
    func allocate(vertexCount: Int, indexCount: Int) -> Allocation? {
        let vStride = MemoryLayout<PackedVoxelVertex>.stride  // 16
        let iStride = MemoryLayout<UInt32>.stride             // 4
        let vBytes = align(vertexCount * vStride)
        let iBytes = align(indexCount * iStride)

        // Try free list first (best-fit), then bump pointer
        let vOffset = allocFromFreeList(&vertexFreeList, size: vBytes)
                   ?? allocFromBump(&vertexBumpOffset, capacity: vertexCapacity, size: vBytes)

        guard let vertexOff = vOffset else { return nil }

        let iOffset = allocFromFreeList(&indexFreeList, size: iBytes)
                   ?? allocFromBump(&indexBumpOffset, capacity: indexCapacity, size: iBytes)

        guard let indexOff = iOffset else {
            // Rollback vertex allocation — return it to free list
            returnToFreeList(&vertexFreeList, offset: vertexOff, size: vBytes)
            return nil
        }

        vertexBytesUsed += vBytes
        indexBytesUsed += iBytes
        allocationCount += 1

        return Allocation(
            vertexOffset: vertexOff,
            indexOffset: indexOff,
            vertexBytes: vBytes,
            indexBytes: iBytes,
            vertexCount: vertexCount,
            indexCount: indexCount
        )
    }

    // MARK: - Free

    /// Return an allocation's space to the free lists for reuse.
    func free(_ allocation: Allocation) {
        returnToFreeList(&vertexFreeList, offset: allocation.vertexOffset, size: allocation.vertexBytes)
        returnToFreeList(&indexFreeList, offset: allocation.indexOffset, size: allocation.indexBytes)
        vertexBytesUsed -= allocation.vertexBytes
        indexBytesUsed -= allocation.indexBytes
        allocationCount -= 1
    }

    // MARK: - Copy Data

    /// Copy vertex and index arrays into the mega-buffer at the allocation's offsets.
    func copyData(allocation: Allocation,
                  vertices: UnsafeRawPointer, vertexBytes: Int,
                  indices: UnsafeRawPointer, indexBytes: Int) {
        memcpy(vertexBuffer.contents().advanced(by: allocation.vertexOffset), vertices, vertexBytes)
        memcpy(indexBuffer.contents().advanced(by: allocation.indexOffset), indices, indexBytes)
    }

    // MARK: - Reset

    /// Full reset — drops everything. Use on teleport or major world change.
    func reset() {
        vertexBumpOffset = 0
        indexBumpOffset = 0
        vertexFreeList.removeAll(keepingCapacity: true)
        indexFreeList.removeAll(keepingCapacity: true)
        vertexBytesUsed = 0
        indexBytesUsed = 0
        allocationCount = 0
    }

    // MARK: - Utilization

    var vertexUtilization: Float {
        Float(vertexBytesUsed) / Float(vertexCapacity)
    }

    var indexUtilization: Float {
        Float(indexBytesUsed) / Float(indexCapacity)
    }

    // MARK: - Private Helpers

    @inline(__always)
    private func align(_ size: Int) -> Int {
        (size + alignment - 1) & ~(alignment - 1)
    }

    /// Try to allocate from free list using best-fit strategy.
    private func allocFromFreeList(_ freeList: inout [(offset: Int, size: Int)], size: Int) -> Int? {
        var bestIdx = -1
        var bestSize = Int.max

        for i in 0..<freeList.count {
            let block = freeList[i]
            if block.size >= size && block.size < bestSize {
                bestIdx = i
                bestSize = block.size
                if block.size == size { break }  // perfect fit, stop early
            }
        }

        guard bestIdx >= 0 else { return nil }

        let block = freeList[bestIdx]
        let offset = block.offset
        let remaining = block.size - size

        if remaining > 0 {
            // Shrink the free block
            freeList[bestIdx] = (offset: block.offset + size, size: remaining)
        } else {
            // Exact fit — remove block
            freeList.remove(at: bestIdx)
        }

        return offset
    }

    /// Allocate from bump pointer region.
    private func allocFromBump(_ bump: inout Int, capacity: Int, size: Int) -> Int? {
        let offset = bump
        guard offset + size <= capacity else { return nil }
        bump = offset + size
        return offset
    }

    /// Return space to free list with coalescing of adjacent blocks.
    private func returnToFreeList(_ freeList: inout [(offset: Int, size: Int)], offset: Int, size: Int) {
        // Find insertion point (keep sorted by offset for coalescing)
        var insertIdx = freeList.count
        for i in 0..<freeList.count {
            if freeList[i].offset > offset {
                insertIdx = i
                break
            }
        }

        freeList.insert((offset: offset, size: size), at: insertIdx)

        // Coalesce with right neighbor
        if insertIdx + 1 < freeList.count {
            let right = freeList[insertIdx + 1]
            if freeList[insertIdx].offset + freeList[insertIdx].size == right.offset {
                freeList[insertIdx].size += right.size
                freeList.remove(at: insertIdx + 1)
            }
        }

        // Coalesce with left neighbor
        if insertIdx > 0 {
            let left = freeList[insertIdx - 1]
            if left.offset + left.size == freeList[insertIdx].offset {
                freeList[insertIdx - 1].size += freeList[insertIdx].size
                freeList.remove(at: insertIdx)
            }
        }
    }
}
