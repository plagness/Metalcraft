import Metal
import simd

/// Packed vertex format: 16 bytes (vs 48 for VoxelVertex).
/// Positions are LOCAL to chunk [0..16]. World origin comes from ChunkInfo buffer.
struct PackedVoxelVertex {
    var px: Float16       // 2 bytes — local X
    var py: Float16       // 2 bytes — local Y
    var pz: Float16       // 2 bytes — local Z
    var normalIdx: UInt8  // 1 byte  — 0..5 = ±X,±Y,±Z
    var _pad0: UInt8      // 1 byte  — alignment
    var u: Float16        // 2 bytes — UV.u
    var v: Float16        // 2 bytes — UV.v
    var r: UInt8          // 1 byte
    var g: UInt8          // 1 byte
    var b: UInt8          // 1 byte
    var a: UInt8          // 1 byte
}   // = 16 bytes total

/// CPU-side greedy mesher that generates optimized voxel meshes.
/// For step=1: true greedy meshing — merges adjacent same-color faces into larger quads.
/// For step>1 (LOD): simpler per-block approach.
///
/// Returns raw arrays — caller is responsible for copying into mega-buffer (MeshAllocator).
class GreedyMesher {

    init() {}

    /// Generate mesh for a chunk. Returns raw vertex/index arrays (no MTLBuffer allocation).
    func mesh(chunk: Chunk,
              neighbors: [SIMD3<Int32>: Chunk] = [:],
              step: Int = 1) -> (vertices: [PackedVoxelVertex], indices: [UInt32])? {

        if step > 1 {
            return meshLOD(chunk: chunk, neighbors: neighbors, step: step)
        }

        var vertices: [PackedVoxelVertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity(2048)
        indices.reserveCapacity(4096)

        let cs = CHUNK_SIZE

        // Reusable 16×16 mask — block rawValue (0 = no face)
        var mask = [UInt16](repeating: 0, count: cs * cs)

        // 6 face directions: 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
        for dir in 0..<6 {
            let axis = dir >> 1  // 0=X, 1=Y, 2=Z
            let positive = (dir & 1) == 0
            let normalIdx = UInt8(dir)  // direct mapping: dir → normalIdx

            for slice in 0..<cs {
                // Clear mask
                for i in 0..<cs*cs { mask[i] = 0 }

                // Build mask: which faces are visible at this slice
                for u in 0..<cs {
                    for v in 0..<cs {
                        // Map (slice, u, v) → (x, y, z)
                        let (lx, ly, lz) = mapCoords(axis: axis, slice: slice, u: u, v: v)
                        let block = chunk.getBlock(x: lx, y: ly, z: lz)
                        guard block != .air, block != .water else { continue }

                        // Neighbor in face direction
                        let (nx, ny, nz): (Int, Int, Int)
                        if positive {
                            nx = lx + (axis == 0 ? 1 : 0)
                            ny = ly + (axis == 1 ? 1 : 0)
                            nz = lz + (axis == 2 ? 1 : 0)
                        } else {
                            nx = lx - (axis == 0 ? 1 : 0)
                            ny = ly - (axis == 1 ? 1 : 0)
                            nz = lz - (axis == 2 ? 1 : 0)
                        }

                        if isFaceVisible(chunk: chunk, neighbors: neighbors,
                                         nx: nx, ny: ny, nz: nz, sourceBlock: block) {
                            mask[u * cs + v] = block.rawValue
                        }
                    }
                }

                // Greedy merge: scan mask, merge same-type rectangles
                var u = 0
                while u < cs {
                    var v = 0
                    while v < cs {
                        let type = mask[u * cs + v]
                        guard type != 0 else { v += 1; continue }

                        // Extend width (v direction)
                        var width = 1
                        while v + width < cs && mask[u * cs + v + width] == type {
                            width += 1
                        }

                        // Extend height (u direction)
                        var height = 1
                        heightLoop: while u + height < cs {
                            for w in v..<(v + width) {
                                if mask[(u + height) * cs + w] != type {
                                    break heightLoop
                                }
                            }
                            height += 1
                        }

                        // Emit merged quad
                        let color = BlockRegistry.getProperties(
                            BlockType(rawValue: type) ?? .stone
                        ).color

                        emitGreedyQuad(&vertices, &indices,
                                       axis: axis, positive: positive,
                                       slice: slice, u: u, v: v,
                                       width: width, height: height,
                                       normalIdx: normalIdx, color: color)

                        // Clear merged area
                        for du in 0..<height {
                            for dv in 0..<width {
                                mask[(u + du) * cs + v + dv] = 0
                            }
                        }

                        v += width
                    }
                    u += 1
                }
            }
        }

        guard !vertices.isEmpty else { return nil }
        return (vertices, indices)
    }

    // MARK: - Coordinate Mapping

    /// Map (axis, slice, u, v) to (x, y, z).
    /// axis 0 (X): slice=x, u=y, v=z
    /// axis 1 (Y): slice=y, u=x, v=z
    /// axis 2 (Z): slice=z, u=x, v=y
    @inline(__always)
    private func mapCoords(axis: Int, slice: Int, u: Int, v: Int) -> (Int, Int, Int) {
        switch axis {
        case 0: return (slice, u, v)
        case 1: return (u, slice, v)
        default: return (u, v, slice)
        }
    }

    // MARK: - Face Visibility

    @inline(__always)
    private func isFaceVisible(chunk: Chunk, neighbors: [SIMD3<Int32>: Chunk],
                                nx: Int, ny: Int, nz: Int,
                                sourceBlock: BlockType) -> Bool {
        let cs = CHUNK_SIZE

        if nx >= 0 && nx < cs && ny >= 0 && ny < cs && nz >= 0 && nz < cs {
            let neighborBlock = chunk.getBlock(x: nx, y: ny, z: nz)
            if neighborBlock == sourceBlock { return false }
            return !BlockRegistry.isOpaque(neighborBlock)
        }

        // At chunk border
        var offset = SIMD3<Int32>(0, 0, 0)
        var cx = nx, cy = ny, cz = nz

        if nx < 0      { offset.x = -1; cx = cs + nx }
        else if nx >= cs { offset.x = 1;  cx = nx - cs }
        if ny < 0      { offset.y = -1; cy = cs + ny }
        else if ny >= cs { offset.y = 1;  cy = ny - cs }
        if nz < 0      { offset.z = -1; cz = cs + nz }
        else if nz >= cs { offset.z = 1;  cz = nz - cs }

        cx = max(0, min(cx, cs - 1))
        cy = max(0, min(cy, cs - 1))
        cz = max(0, min(cz, cs - 1))

        let neighborChunkPos = chunk.position &+ offset
        if let neighborChunk = neighbors[neighborChunkPos] {
            let neighborBlock = neighborChunk.getBlock(x: cx, y: cy, z: cz)
            if neighborBlock == sourceBlock { return false }
            return !BlockRegistry.isOpaque(neighborBlock)
        }
        return true
    }

    // MARK: - Greedy Quad Emission (packed, local coords)

    @inline(__always)
    private func emitGreedyQuad(_ vertices: inout [PackedVoxelVertex], _ indices: inout [UInt32],
                                 axis: Int, positive: Bool,
                                 slice: Int, u: Int, v: Int,
                                 width: Int, height: Int,
                                 normalIdx: UInt8, color: SIMD4<Float>) {
        // Compute 4 corners of the merged rectangle in LOCAL space (no worldOrigin)
        let fSlice = Float16(positive ? slice + 1 : slice)
        let fu = Float16(u)
        let fv = Float16(v)
        let fw = Float16(width)
        let fh = Float16(height)

        let r = UInt8(min(255, max(0, color.x * 255.0)))
        let g = UInt8(min(255, max(0, color.y * 255.0)))
        let b = UInt8(min(255, max(0, color.z * 255.0)))
        let a = UInt8(min(255, max(0, color.w * 255.0)))

        let p0x, p0y, p0z, p1x, p1y, p1z, p2x, p2y, p2z, p3x, p3y, p3z: Float16

        switch axis {
        case 0: // X-axis faces
            if positive { // +X
                p0x = fSlice; p0y = fu;      p0z = fv
                p1x = fSlice; p1y = fu;      p1z = fv + fw
                p2x = fSlice; p2y = fu + fh; p2z = fv + fw
                p3x = fSlice; p3y = fu + fh; p3z = fv
            } else { // -X
                p0x = fSlice; p0y = fu;      p0z = fv + fw
                p1x = fSlice; p1y = fu;      p1z = fv
                p2x = fSlice; p2y = fu + fh; p2z = fv
                p3x = fSlice; p3y = fu + fh; p3z = fv + fw
            }
        case 1: // Y-axis faces
            if positive { // +Y
                p0x = fu;      p0y = fSlice; p0z = fv
                p1x = fu + fh; p1y = fSlice; p1z = fv
                p2x = fu + fh; p2y = fSlice; p2z = fv + fw
                p3x = fu;      p3y = fSlice; p3z = fv + fw
            } else { // -Y
                p0x = fu;      p0y = fSlice; p0z = fv + fw
                p1x = fu + fh; p1y = fSlice; p1z = fv + fw
                p2x = fu + fh; p2y = fSlice; p2z = fv
                p3x = fu;      p3y = fSlice; p3z = fv
            }
        default: // Z-axis faces
            if positive { // +Z
                p0x = fu + fh; p0y = fv;      p0z = fSlice
                p1x = fu;      p1y = fv;      p1z = fSlice
                p2x = fu;      p2y = fv + fw; p2z = fSlice
                p3x = fu + fh; p3y = fv + fw; p3z = fSlice
            } else { // -Z
                p0x = fu;      p0y = fv;      p0z = fSlice
                p1x = fu + fh; p1y = fv;      p1z = fSlice
                p2x = fu + fh; p2y = fv + fw; p2z = fSlice
                p3x = fu;      p3y = fv + fw; p3z = fSlice
            }
        }

        let base = UInt32(vertices.count)
        let uvW = Float16(width)
        let uvH = Float16(height)

        vertices.append(PackedVoxelVertex(px: p0x, py: p0y, pz: p0z, normalIdx: normalIdx, _pad0: 0, u: 0, v: uvH, r: r, g: g, b: b, a: a))
        vertices.append(PackedVoxelVertex(px: p1x, py: p1y, pz: p1z, normalIdx: normalIdx, _pad0: 0, u: uvW, v: uvH, r: r, g: g, b: b, a: a))
        vertices.append(PackedVoxelVertex(px: p2x, py: p2y, pz: p2z, normalIdx: normalIdx, _pad0: 0, u: uvW, v: 0, r: r, g: g, b: b, a: a))
        vertices.append(PackedVoxelVertex(px: p3x, py: p3y, pz: p3z, normalIdx: normalIdx, _pad0: 0, u: 0, v: 0, r: r, g: g, b: b, a: a))

        indices.append(contentsOf: [base, base+2, base+1, base, base+3, base+2])
    }

    // MARK: - LOD Meshing (step > 1, simpler per-block approach)

    private func meshLOD(chunk: Chunk,
                          neighbors: [SIMD3<Int32>: Chunk],
                          step: Int) -> (vertices: [PackedVoxelVertex], indices: [UInt32])? {
        var vertices: [PackedVoxelVertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity(1024)
        indices.reserveCapacity(2048)

        let cs = CHUNK_SIZE
        let s = max(1, min(step, cs))
        let fStep = Float16(s)

        var ly = 0
        while ly < cs {
            var lz = 0
            while lz < cs {
                var lx = 0
                while lx < cs {
                    // LOD: scan top-down to find surface block
                    var found: BlockType = .air
                    for checkY in stride(from: min(ly + s - 1, cs - 1), through: ly, by: -1) {
                        let b = chunk.getBlock(x: lx, y: checkY, z: lz)
                        if b != .air && b != .water && b != .tallGrass && b != .redFlower && b != .deadBush {
                            found = b
                            break
                        }
                    }
                    guard found != .air else { lx += s; continue }

                    let color = BlockRegistry.getProperties(found).color
                    let flx = Float16(lx)
                    let fly = Float16(ly)
                    let flz = Float16(lz)

                    // 6 faces with LOD visibility check
                    // +X face (normalIdx = 0)
                    if shouldShowFaceLOD(chunk: chunk, neighbors: neighbors, lx: lx + s, ly: ly, lz: lz, step: s, sourceBlock: found) {
                        addFace(&vertices, &indices, color: color,
                                p0x: flx + fStep, p0y: fly,          p0z: flz,
                                p1x: flx + fStep, p1y: fly,          p1z: flz + fStep,
                                p2x: flx + fStep, p2y: fly + fStep,  p2z: flz + fStep,
                                p3x: flx + fStep, p3y: fly + fStep,  p3z: flz,
                                normalIdx: 0)
                    }
                    // -X face (normalIdx = 1)
                    if shouldShowFaceLOD(chunk: chunk, neighbors: neighbors, lx: lx - s, ly: ly, lz: lz, step: s, sourceBlock: found) {
                        addFace(&vertices, &indices, color: color,
                                p0x: flx, p0y: fly,          p0z: flz + fStep,
                                p1x: flx, p1y: fly,          p1z: flz,
                                p2x: flx, p2y: fly + fStep,  p2z: flz,
                                p3x: flx, p3y: fly + fStep,  p3z: flz + fStep,
                                normalIdx: 1)
                    }
                    // +Y face (normalIdx = 2)
                    if shouldShowFaceLOD(chunk: chunk, neighbors: neighbors, lx: lx, ly: ly + s, lz: lz, step: s, sourceBlock: found) {
                        addFace(&vertices, &indices, color: color,
                                p0x: flx,          p0y: fly + fStep, p0z: flz,
                                p1x: flx + fStep,  p1y: fly + fStep, p1z: flz,
                                p2x: flx + fStep,  p2y: fly + fStep, p2z: flz + fStep,
                                p3x: flx,          p3y: fly + fStep, p3z: flz + fStep,
                                normalIdx: 2)
                    }
                    // -Y face (normalIdx = 3)
                    if shouldShowFaceLOD(chunk: chunk, neighbors: neighbors, lx: lx, ly: ly - s, lz: lz, step: s, sourceBlock: found) {
                        addFace(&vertices, &indices, color: color,
                                p0x: flx,          p0y: fly, p0z: flz + fStep,
                                p1x: flx + fStep,  p1y: fly, p1z: flz + fStep,
                                p2x: flx + fStep,  p2y: fly, p2z: flz,
                                p3x: flx,          p3y: fly, p3z: flz,
                                normalIdx: 3)
                    }
                    // +Z face (normalIdx = 4)
                    if shouldShowFaceLOD(chunk: chunk, neighbors: neighbors, lx: lx, ly: ly, lz: lz + s, step: s, sourceBlock: found) {
                        addFace(&vertices, &indices, color: color,
                                p0x: flx + fStep, p0y: fly,          p0z: flz + fStep,
                                p1x: flx,         p1y: fly,          p1z: flz + fStep,
                                p2x: flx,         p2y: fly + fStep,  p2z: flz + fStep,
                                p3x: flx + fStep, p3y: fly + fStep,  p3z: flz + fStep,
                                normalIdx: 4)
                    }
                    // -Z face (normalIdx = 5)
                    if shouldShowFaceLOD(chunk: chunk, neighbors: neighbors, lx: lx, ly: ly, lz: lz - s, step: s, sourceBlock: found) {
                        addFace(&vertices, &indices, color: color,
                                p0x: flx,         p0y: fly,          p0z: flz,
                                p1x: flx + fStep, p1y: fly,          p1z: flz,
                                p2x: flx + fStep, p2y: fly + fStep,  p2z: flz,
                                p3x: flx,         p3y: fly + fStep,  p3z: flz,
                                normalIdx: 5)
                    }

                    lx += s
                }
                lz += s
            }
            ly += s
        }

        guard !vertices.isEmpty else { return nil }
        return (vertices, indices)
    }

    // MARK: - LOD Face Visibility

    @inline(__always)
    private func shouldShowFaceLOD(chunk: Chunk, neighbors: [SIMD3<Int32>: Chunk],
                                    lx: Int, ly: Int, lz: Int, step: Int,
                                    sourceBlock: BlockType) -> Bool {
        let cs = CHUNK_SIZE

        if lx >= 0 && lx < cs && ly >= 0 && ly < cs && lz >= 0 && lz < cs {
            let neighborBlock = chunk.getBlock(x: lx, y: ly, z: lz)
            if neighborBlock == sourceBlock { return false }
            return !BlockRegistry.isOpaque(neighborBlock)
        }

        var offset = SIMD3<Int32>(0, 0, 0)
        var nx = lx, ny = ly, nz = lz

        if lx < 0      { offset.x = -1; nx = cs + lx }
        else if lx >= cs { offset.x = 1;  nx = lx - cs }
        if ly < 0      { offset.y = -1; ny = cs + ly }
        else if ly >= cs { offset.y = 1;  ny = ly - cs }
        if lz < 0      { offset.z = -1; nz = cs + lz }
        else if lz >= cs { offset.z = 1;  nz = lz - cs }

        nx = max(0, min(nx, cs - 1))
        ny = max(0, min(ny, cs - 1))
        nz = max(0, min(nz, cs - 1))

        let neighborChunkPos = chunk.position &+ offset
        if let neighborChunk = neighbors[neighborChunkPos] {
            let neighborBlock = neighborChunk.getBlock(x: nx, y: ny, z: nz)
            if neighborBlock == sourceBlock { return false }
            return !BlockRegistry.isOpaque(neighborBlock)
        }
        return true
    }

    // MARK: - Simple Quad Emission (for LOD, packed local coords)

    @inline(__always)
    private func addFace(_ vertices: inout [PackedVoxelVertex], _ indices: inout [UInt32],
                         color: SIMD4<Float>,
                         p0x: Float16, p0y: Float16, p0z: Float16,
                         p1x: Float16, p1y: Float16, p1z: Float16,
                         p2x: Float16, p2y: Float16, p2z: Float16,
                         p3x: Float16, p3y: Float16, p3z: Float16,
                         normalIdx: UInt8) {
        let base = UInt32(vertices.count)

        let r = UInt8(min(255, max(0, color.x * 255.0)))
        let g = UInt8(min(255, max(0, color.y * 255.0)))
        let b = UInt8(min(255, max(0, color.z * 255.0)))
        let a = UInt8(min(255, max(0, color.w * 255.0)))

        vertices.append(PackedVoxelVertex(px: p0x, py: p0y, pz: p0z, normalIdx: normalIdx, _pad0: 0, u: 0, v: 1, r: r, g: g, b: b, a: a))
        vertices.append(PackedVoxelVertex(px: p1x, py: p1y, pz: p1z, normalIdx: normalIdx, _pad0: 0, u: 1, v: 1, r: r, g: g, b: b, a: a))
        vertices.append(PackedVoxelVertex(px: p2x, py: p2y, pz: p2z, normalIdx: normalIdx, _pad0: 0, u: 1, v: 0, r: r, g: g, b: b, a: a))
        vertices.append(PackedVoxelVertex(px: p3x, py: p3y, pz: p3z, normalIdx: normalIdx, _pad0: 0, u: 0, v: 0, r: r, g: g, b: b, a: a))

        indices.append(contentsOf: [base, base+2, base+1, base, base+3, base+2])
    }
}
