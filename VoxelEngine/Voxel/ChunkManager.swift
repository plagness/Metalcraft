import Metal
import simd

/// Manages chunk lifecycle: loading, terrain generation, meshing, and streaming.
/// Uses GPU compute for terrain generation (10-50x faster than CPU).
///
/// Optimized for 16GB Apple Silicon:
///   - Memory cap: ~800MB for chunks (100K chunks max)
///   - Loading throttle: skip if too many in-flight
///   - Ring-based iteration: only checks frontier, not entire view distance
///   - Circular view distance (not square) — 21% fewer chunks
///
/// LOD system:
///   Near      (0-10):   step=1  (full 16³)
///   Mid       (10-24):  step=2  (8³ effective)
///   Far       (24-48):  step=4  (4³ effective)
///   Very-far  (48-100): step=8  (2³ effective)
///   Ultra-far (100-128):step=16 (1³ effective)
class ChunkManager {

    private let device: MTLDevice
    private let gpuTerrainGenerator: GPUTerrainGenerator
    private let cpuTerrainGenerator: TerrainGenerator
    private let mesher: GreedyMesher
    let meshAllocator: MeshAllocator

    /// All currently loaded chunks keyed by chunk coordinate.
    private(set) var chunks: [SIMD3<Int32>: Chunk] = [:]

    /// Chunks that have meshes and are ready to render.
    private(set) var renderableChunks: [Chunk] = []

    /// Configuration
    let viewDistance: Int = 64      // chunks radius for LOADING (64 * 16 = 1024 blocks)
    let maxRenderChunks: Int = 4500 // cap draws to maintain 40+ FPS (farthest chunks culled)
    let maxLoadPerFrame: Int = 32   // balanced: fast enough loading, no CPU hog
    let maxMeshPerFrame: Int = 24   // reasonable meshing throughput
    let maxInFlightGen: Int = 64    // throttle: don't overload GPU command queue
    let maxChunkCount: Int = 100_000 // ~800MB memory cap

    // MARK: - Background Threading

    private let genQueue = DispatchQueue(label: "com.voxel.chunkGen", qos: .userInitiated,
                                         attributes: .concurrent)
    private let meshQueue = DispatchQueue(label: "com.voxel.chunkMesh", qos: .userInitiated,
                                          attributes: .concurrent)

    private var inFlightGenPositions: Set<SIMD3<Int32>> = []
    private var inFlightMeshPositions: Set<SIMD3<Int32>> = []

    private var pendingChunks: [(SIMD3<Int32>, Chunk)] = []
    private let pendingLock = NSLock()

    private var pendingMeshResults: [(Chunk, [PackedVoxelVertex]?, [UInt32]?, Bool, Int)] = []
    private let meshResultLock = NSLock()

    /// Positions that were re-meshed this frame (for water cache invalidation)
    private(set) var recentlyRemeshedPositions: [SIMD3<Int32>] = []

    /// Track camera chunk for LOD re-evaluation
    private var lastCameraChunk: SIMD3<Int32> = SIMD3<Int32>(Int32.max, Int32.max, Int32.max)

    /// Dirty chunks — direct references, no dictionary lookup needed
    private var dirtyChunkQueue: ContiguousArray<Chunk> = []
    private var dirtyChunkSet: Set<ObjectIdentifier> = []  // dedup guard

    /// Frame counter for throttled operations
    private var frameCount: Int = 0

    /// Frustum cull cache — skip re-cull when camera hasn't moved/rotated
    private var lastCullPosition: SIMD3<Float> = SIMD3<Float>(Float.greatestFiniteMagnitude, 0, 0)
    private var lastCullForward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    private var lastCullFrameCount: Int = -100
    private var newMeshesSinceLastCull: Bool = true

    /// Cached load queue — rebuilt when camera moves to new chunk
    private var cachedLoadQueue: [(SIMD3<Int32>, Float)] = []
    private var loadQueueIndex: Int = 0
    private var loadQueueCameraChunk: SIMD3<Int32> = SIMD3<Int32>(Int32.max, Int32.max, Int32.max)

    init(device: MTLDevice, seed: Int = 42) {
        self.device = device
        self.gpuTerrainGenerator = GPUTerrainGenerator(device: device, seed: seed)
        self.cpuTerrainGenerator = TerrainGenerator(seed: seed)
        self.mesher = GreedyMesher()
        self.meshAllocator = MeshAllocator(device: device, vertexMB: 128, indexMB: 64)
    }

    /// Mark a chunk as dirty and add to meshing queue (O(1), deduped)
    private func markDirty(_ chunk: Chunk) {
        chunk.isDirty = true
        let id = ObjectIdentifier(chunk)
        if dirtyChunkSet.insert(id).inserted {
            dirtyChunkQueue.append(chunk)
        }
    }

    // MARK: - LOD Helpers

    func lodStep(for pos: SIMD3<Int32>, cameraChunk: SIMD3<Int32>) -> Int {
        let dx = Float(pos.x - cameraChunk.x)
        let dz = Float(pos.z - cameraChunk.z)
        let dist = (dx * dx + dz * dz).squareRoot()  // circular, not square
        if dist <= 40  { return 1 }
        if dist <= 70  { return 2 }
        if dist <= 100 { return 4 }
        return 8
    }

    func verticalRange(forDist dist: Int) -> ClosedRange<Int32> {
        if dist <= 12  { return -2...6 }
        if dist <= 30  { return  0...4 }
        if dist <= 60  { return  0...3 }
        return 0...2
    }

    // MARK: - Update

    func update(cameraPosition: SIMD3<Float>, cameraForward: SIMD3<Float>, frustum: Frustum) {
        let cameraChunk = worldToChunk(cameraPosition)
        frameCount += 1

        // 1. Integrate completed background work
        integrateCompletedChunks()
        integrateCompletedMeshes()

        // 2. Camera moved — re-evaluate LOD
        if cameraChunk != lastCameraChunk {
            markLODChanges(cameraChunk: cameraChunk)
            lastCameraChunk = cameraChunk
        }

        // 3. Enqueue new chunk loads (ring-based, throttled)
        enqueueChunkLoads(center: cameraChunk)

        // 4. Unload distant chunks — throttled to every 30 frames
        if frameCount % 30 == 0 {
            unloadDistantChunks(center: cameraChunk)
        }

        // 5. Enqueue dirty chunks for meshing (uses dirty set, not full scan)
        enqueueMeshing(cameraChunk: cameraChunk)

        // 6. Build render list
        updateRenderableList(cameraPosition: cameraPosition, cameraForward: cameraForward, frustum: frustum)
    }

    private func markLODChanges(cameraChunk: SIMD3<Int32>) {
        for (pos, chunk) in chunks {
            guard chunk.isMeshed, !chunk.isEmpty else { continue }
            let desiredStep = lodStep(for: pos, cameraChunk: cameraChunk)
            if chunk.meshLODStep != desiredStep {
                markDirty(chunk)
            }
        }
    }

    // MARK: - Chunk Loading (cached queue, rebuilt on camera move)

    /// Rebuild the full load queue when camera enters a new chunk.
    /// Ring-based iteration: visits chunks from center outward — naturally distance-ordered, no sort.
    private func rebuildLoadQueue(center: SIMD3<Int32>) {
        cachedLoadQueue.removeAll(keepingCapacity: true)
        loadQueueIndex = 0
        loadQueueCameraChunk = center

        let vd = Int32(viewDistance)
        let vdSq = vd * vd

        // Ring 0 = center, ring 1 = 8 surrounding, etc.
        // This gives L∞ distance order (close enough to L2 for chunk loading priority).
        for ring in Int32(0)...vd {
            for dx in -ring...ring {
                for dz in -ring...ring {
                    // Only process border of this ring (interior already done)
                    guard abs(dx) == ring || abs(dz) == ring else { continue }

                    let distSq = dx * dx + dz * dz
                    if distSq > vdSq { continue }

                    let hdist = max(abs(dx), abs(dz))
                    let yRange = verticalRange(forDist: Int(hdist))

                    for dy in yRange {
                        let pos = SIMD3<Int32>(center.x + dx, dy, center.z + dz)
                        cachedLoadQueue.append((pos, Float(distSq)))
                    }
                }
            }
        }
    }

    private func enqueueChunkLoads(center: SIMD3<Int32>) {
        // Throttle: skip if too many in-flight or at memory cap
        guard inFlightGenPositions.count < maxInFlightGen,
              chunks.count < maxChunkCount else { return }

        // Rebuild queue when camera moves to a new chunk
        if center != loadQueueCameraChunk {
            rebuildLoadQueue(center: center)
        }

        // Walk the sorted queue and pick chunks that still need loading
        var batch: [SIMD3<Int32>] = []
        let budget = min(maxLoadPerFrame, maxInFlightGen - inFlightGenPositions.count)

        while loadQueueIndex < cachedLoadQueue.count && batch.count < budget {
            let (pos, _) = cachedLoadQueue[loadQueueIndex]
            loadQueueIndex += 1

            if chunks[pos] == nil && !inFlightGenPositions.contains(pos) {
                batch.append(pos)
            }
        }

        guard !batch.isEmpty else { return }

        for pos in batch {
            inFlightGenPositions.insert(pos)
        }

        let device = self.device
        let gpuGen = self.gpuTerrainGenerator

        genQueue.async { [weak self] in
            var newChunks: [(SIMD3<Int32>, Chunk)] = []
            var gpuChunks: [Chunk] = []

            for pos in batch {
                let chunk = Chunk(position: pos, device: device)
                newChunks.append((pos, chunk))
                gpuChunks.append(chunk)
            }

            gpuGen.generateBatch(chunks: gpuChunks)

            self?.pendingLock.lock()
            self?.pendingChunks.append(contentsOf: newChunks)
            self?.pendingLock.unlock()
        }
    }

    private func integrateCompletedChunks() {
        pendingLock.lock()
        let completed = pendingChunks
        pendingChunks.removeAll(keepingCapacity: true)
        pendingLock.unlock()

        guard !completed.isEmpty else { return }
        // NOTE: Don't set meshedChunksDirty here — new chunks aren't meshed yet.
        // meshedChunks is updated incrementally in integrateCompletedMeshes().

        let neighborOffsets: [SIMD3<Int32>] = [
            SIMD3<Int32>( 1, 0, 0), SIMD3<Int32>(-1, 0, 0),
            SIMD3<Int32>( 0, 1, 0), SIMD3<Int32>( 0,-1, 0),
            SIMD3<Int32>( 0, 0, 1), SIMD3<Int32>( 0, 0,-1),
        ]

        for (pos, chunk) in completed {
            inFlightGenPositions.remove(pos)

            // Memory check — don't add if over budget
            guard chunks.count < maxChunkCount else { continue }

            chunks[pos] = chunk

            // Mark new chunk dirty for meshing
            if chunk.isDirty {
                markDirty(chunk)
            }

            for offset in neighborOffsets {
                let neighborPos = pos &+ offset
                if let neighbor = chunks[neighborPos], neighbor.isMeshed,
                   neighbor.meshLODStep == 1 {
                    markDirty(neighbor)
                }
            }
        }
    }

    // MARK: - Background Meshing

    private func enqueueMeshing(cameraChunk: SIMD3<Int32>) {
        // Throttle: only scan every 3 frames (meshing is async anyway)
        guard frameCount % 3 == 0 else { return }
        guard inFlightMeshPositions.count < 48, !dirtyChunkQueue.isEmpty else { return }

        // Collect candidates directly from queue (FIFO — no sort needed).
        // Queue is roughly distance-ordered: chunks load center→outward.
        // We take up to maxMeshPerFrame non-in-flight candidates.
        var dispatched = 0
        var writeIdx = 0
        for readIdx in 0..<dirtyChunkQueue.count {
            let chunk = dirtyChunkQueue[readIdx]
            // Skip stale entries
            if !chunk.isDirty || chunk.isEmpty {
                dirtyChunkSet.remove(ObjectIdentifier(chunk))
                continue
            }
            // Keep valid entries in queue
            dirtyChunkQueue[writeIdx] = chunk
            writeIdx += 1

            // Dispatch if not already in-flight and we have budget
            if dispatched < maxMeshPerFrame && !inFlightMeshPositions.contains(chunk.position) {
                let step = lodStep(for: chunk.position, cameraChunk: cameraChunk)
                dispatchMesh(chunk: chunk, step: step)
                dispatched += 1
            }
        }
        dirtyChunkQueue.removeSubrange(writeIdx..<dirtyChunkQueue.count)
    }

    /// Dispatch a single chunk for background meshing.
    private func dispatchMesh(chunk: Chunk, step: Int) {
        let pos = chunk.position
        inFlightMeshPositions.insert(pos)
        chunk.isDirty = false
        dirtyChunkSet.remove(ObjectIdentifier(chunk))

        var neighbors: [SIMD3<Int32>: Chunk] = [:]
        if step == 1 {
            let offsets: [SIMD3<Int32>] = [
                SIMD3<Int32>( 1, 0, 0), SIMD3<Int32>(-1, 0, 0),
                SIMD3<Int32>( 0, 1, 0), SIMD3<Int32>( 0,-1, 0),
                SIMD3<Int32>( 0, 0, 1), SIMD3<Int32>( 0, 0,-1),
            ]
            for offset in offsets {
                let neighborPos = pos &+ offset
                if let neighborChunk = chunks[neighborPos] {
                    neighbors[neighborPos] = neighborChunk
                }
            }
        }

        let mesher = self.mesher
        let lodStep = step

        meshQueue.async { [weak self] in
            if let result = mesher.mesh(chunk: chunk, neighbors: neighbors, step: lodStep) {
                self?.meshResultLock.lock()
                self?.pendingMeshResults.append((chunk, result.vertices, result.indices, false, lodStep))
                self?.meshResultLock.unlock()
            } else {
                self?.meshResultLock.lock()
                self?.pendingMeshResults.append((chunk, nil, nil, true, lodStep))
                self?.meshResultLock.unlock()
            }
        }
    }

    private func integrateCompletedMeshes() {
        meshResultLock.lock()
        let results = pendingMeshResults
        pendingMeshResults.removeAll(keepingCapacity: true)
        meshResultLock.unlock()

        recentlyRemeshedPositions.removeAll(keepingCapacity: true)
        guard !results.isEmpty else { return }
        newMeshesSinceLastCull = true

        for (chunk, vertices, indices, empty, lodStep) in results {
            inFlightMeshPositions.remove(chunk.position)

            let wasMeshed = chunk.isMeshed && !chunk.isEmpty

            // Free previous allocation if re-meshing
            if let oldAlloc = chunk.meshAllocation {
                meshAllocator.free(oldAlloc)
                chunk.meshAllocation = nil
            }

            if empty {
                chunk.isEmpty = true
                chunk.isMeshed = false
                chunk.vertexCount = 0
                chunk.indexCount = 0
                if wasMeshed { meshedChunksDirty = true }
            } else if let verts = vertices, let idxs = indices {
                // Allocate from mega-buffer
                if let alloc = meshAllocator.allocate(vertexCount: verts.count, indexCount: idxs.count) {
                    // Copy data into mega-buffer
                    verts.withUnsafeBufferPointer { vPtr in
                        idxs.withUnsafeBufferPointer { iPtr in
                            meshAllocator.copyData(
                                allocation: alloc,
                                vertices: vPtr.baseAddress!,
                                vertexBytes: verts.count * MemoryLayout<PackedVoxelVertex>.stride,
                                indices: iPtr.baseAddress!,
                                indexBytes: idxs.count * MemoryLayout<UInt32>.stride
                            )
                        }
                    }
                    chunk.meshAllocation = alloc
                    chunk.vertexCount = verts.count
                    chunk.indexCount = idxs.count
                    chunk.isMeshed = true
                    chunk.meshLODStep = lodStep

                    if !wasMeshed {
                        meshedChunks.append(chunk)
                    }
                }
                // else: allocation failed (out of space) — chunk stays un-meshed, will retry
            }
            recentlyRemeshedPositions.append(chunk.position)
        }
    }

    // MARK: - Unloading

    private func unloadDistantChunks(center: SIMD3<Int32>) {
        let maxDist = Int32(viewDistance + 2)
        let maxDistSq = maxDist * maxDist
        var toRemove: [SIMD3<Int32>] = []

        for (pos, _) in chunks {
            let dx = pos.x - center.x
            let dz = pos.z - center.z
            let distSq = dx * dx + dz * dz

            // Circular unloading (matches circular loading)
            if distSq > maxDistSq {
                toRemove.append(pos)
                continue
            }

            let hdist = max(abs(dx), abs(dz))
            let yRange = verticalRange(forDist: Int(hdist))
            if !yRange.contains(pos.y) {
                toRemove.append(pos)
            }
        }

        if !toRemove.isEmpty { meshedChunksDirty = true }
        for pos in toRemove {
            if let chunk = chunks.removeValue(forKey: pos) {
                // Free mega-buffer allocation
                if let alloc = chunk.meshAllocation {
                    meshAllocator.free(alloc)
                    chunk.meshAllocation = nil
                }
                dirtyChunkSet.remove(ObjectIdentifier(chunk))
            }
            inFlightGenPositions.remove(pos)
            inFlightMeshPositions.remove(pos)
        }
    }

    // MARK: - Render List

    /// Index-based sort buffer — value types only, zero retain/release overhead.
    private var sortIndices: [(index: Int, distSq: Float)] = []
    /// Track camera position for sort-skip optimization
    private var lastSortPosition: SIMD3<Float> = SIMD3<Float>(Float.greatestFiniteMagnitude, 0, 0)
    /// All meshed non-empty chunks — avoids iterating full dictionary every frame
    private var meshedChunks: ContiguousArray<Chunk> = []
    private var meshedChunksDirty: Bool = true
    /// Incremented every time renderableChunks changes — used by ICB to skip re-encoding
    private(set) var renderableListVersion: UInt64 = 0

    /// Call when chunks are added/removed or mesh state changes
    func invalidateMeshedChunks() { meshedChunksDirty = true }

    private func updateRenderableList(cameraPosition: SIMD3<Float>, cameraForward: SIMD3<Float>, frustum: Frustum) {
        // Full rebuild only on unload or chunk→empty transitions (infrequent)
        if meshedChunksDirty {
            meshedChunks.removeAll(keepingCapacity: true)
            for (_, chunk) in chunks {
                guard chunk.isMeshed, !chunk.isEmpty,
                      chunk.meshAllocation != nil,
                      chunk.indexCount > 0 else { continue }
                meshedChunks.append(chunk)
            }
            meshedChunksDirty = false
            newMeshesSinceLastCull = true
        }

        // Skip frustum cull if camera hasn't moved OR rotated significantly.
        // Rotation detection: dot(lastForward, currentForward) < 0.998 ≈ ~3.6° rotation
        let dd = cameraPosition - lastCullPosition
        let cullMoved = dd.x * dd.x + dd.y * dd.y + dd.z * dd.z
        let forwardDot = simd_dot(lastCullForward, cameraForward)
        let cameraRotated = forwardDot < 0.998
        let framesSinceLastCull = frameCount - lastCullFrameCount
        let needsCull = cullMoved > 16.0
                     || cameraRotated
                     || (newMeshesSinceLastCull && framesSinceLastCull >= 15)
                     || framesSinceLastCull >= 30

        if needsCull {
            sortIndices.removeAll(keepingCapacity: true)
            meshedChunks.withUnsafeBufferPointer { chunks in
                for i in 0..<chunks.count {
                    let chunk = chunks[i]
                    guard chunk.meshAllocation != nil, chunk.indexCount > 0 else { continue }
                    if frustum.containsAABB(chunk.aabb) {
                        let d = chunk.aabb.center - cameraPosition
                        let distSq = d.x * d.x + d.y * d.y + d.z * d.z
                        sortIndices.append((i, distSq))
                    }
                }
            }
            lastCullFrameCount = frameCount
            lastCullPosition = cameraPosition
            lastCullForward = cameraForward
            newMeshesSinceLastCull = false

            // Always sort — needed for render distance cap (nearest first)
            sortIndices.sort { $0.distSq < $1.distSq }
            lastSortPosition = cameraPosition

            // Rebuild renderableChunks from indices, capping at maxRenderChunks
            let drawCount = min(sortIndices.count, maxRenderChunks)
            renderableChunks.removeAll(keepingCapacity: true)
            renderableChunks.reserveCapacity(drawCount)
            meshedChunks.withUnsafeBufferPointer { chunks in
                for i in 0..<drawCount {
                    renderableChunks.append(chunks[sortIndices[i].index])
                }
            }
            renderableListVersion &+= 1
        }
    }

    // MARK: - Coordinate Conversion

    func worldToChunk(_ worldPos: SIMD3<Float>) -> SIMD3<Int32> {
        return SIMD3<Int32>(
            Int32(floor(worldPos.x / Float(CHUNK_SIZE))),
            Int32(floor(worldPos.y / Float(CHUNK_SIZE))),
            Int32(floor(worldPos.z / Float(CHUNK_SIZE)))
        )
    }

    /// Stats for debug overlay
    var loadedChunkCount: Int { chunks.count }
    var renderedChunkCount: Int { renderableChunks.count }
    var totalVertices: Int { renderableChunks.reduce(0) { $0 + $1.vertexCount } }
    var totalTriangles: Int { renderableChunks.reduce(0) { $0 + $1.indexCount / 3 } }
}
