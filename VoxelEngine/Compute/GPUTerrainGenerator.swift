import Metal

/// GPU-accelerated terrain generator using Metal compute shaders.
/// Generates terrain ~10-50x faster than CPU by running noise on all 256 columns in parallel.
/// Uses storageModeShared buffers for zero-copy UMA — GPU writes directly to chunk's blockBuffer.
class GPUTerrainGenerator {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let configBuffer: MTLBuffer

    let seed: Int

    // Terrain parameters (must match CPU TerrainGenerator for consistency)
    let seaLevel: Int32 = 32
    let baseHeight: Int32 = 40
    let heightVariation: Float = 30.0
    let terrainScale: Float = 0.008
    let detailScale: Float = 0.04
    let caveScale: Float = 0.05
    let caveThreshold: Float = 0.72

    /// Config struct matching Metal's TerrainConfig layout exactly.
    struct GPUTerrainConfig {
        var chunkX: Int32
        var chunkY: Int32
        var chunkZ: Int32
        var seed: Int32
        var seaLevel: Int32
        var baseHeight: Int32
        var heightVariation: Float
        var terrainScale: Float
        var detailScale: Float
        var caveScale: Float
        var caveThreshold: Float
        var chunkSize: Int32
    }

    init(device: MTLDevice, seed: Int = 42) {
        self.device = device
        self.seed = seed

        guard let queue = device.makeCommandQueue() else {
            fatalError("GPUTerrainGenerator: failed to create command queue")
        }
        queue.label = "com.voxel.terrainGen"
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "terrain_generate") else {
            fatalError("GPUTerrainGenerator: terrain_generate function not found in default library")
        }

        do {
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("GPUTerrainGenerator: failed to create pipeline: \(error)")
        }

        // Pre-allocate config buffer (reused for each dispatch)
        guard let buf = device.makeBuffer(length: MemoryLayout<GPUTerrainConfig>.stride,
                                           options: .storageModeShared) else {
            fatalError("GPUTerrainGenerator: failed to create config buffer")
        }
        buf.label = "TerrainConfig"
        self.configBuffer = buf

    }

    /// Generate terrain for a chunk on GPU. Blocks until complete.
    /// Writes directly into chunk.blockBuffer (zero-copy UMA).
    func generate(chunk: Chunk) {
        var config = GPUTerrainConfig(
            chunkX: chunk.position.x,
            chunkY: chunk.position.y,
            chunkZ: chunk.position.z,
            seed: Int32(seed),
            seaLevel: seaLevel,
            baseHeight: baseHeight,
            heightVariation: heightVariation,
            terrainScale: terrainScale,
            detailScale: detailScale,
            caveScale: caveScale,
            caveThreshold: caveThreshold,
            chunkSize: Int32(CHUNK_SIZE)
        )

        // Copy config into buffer
        memcpy(configBuffer.contents(), &config, MemoryLayout<GPUTerrainConfig>.stride)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(chunk.blockBuffer, offset: 0, index: 0)
        encoder.setBuffer(configBuffer, offset: 0, index: 1)

        // Dispatch 16x16 threads (one per XZ column)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: CHUNK_SIZE, height: CHUNK_SIZE, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        chunk.updateIsEmpty()
        chunk.isDirty = true
    }

    /// Generate terrain for a batch of chunks. Single encoder, one config buffer per call.
    /// Safe for concurrent calls (each gets its own config buffer).
    func generateBatch(chunks: [Chunk]) {
        guard !chunks.isEmpty else { return }

        let configStride = MemoryLayout<GPUTerrainConfig>.stride
        let count = chunks.count

        // One allocation per batch (not per chunk) — safe for concurrent genQueue
        guard let batchConfig = device.makeBuffer(length: configStride * count,
                                                   options: .storageModeShared) else { return }
        batchConfig.label = "TerrainBatchConfig"

        let ptr = batchConfig.contents().bindMemory(to: GPUTerrainConfig.self, capacity: count)
        for i in 0..<count {
            let chunk = chunks[i]
            ptr[i] = GPUTerrainConfig(
                chunkX: chunk.position.x,
                chunkY: chunk.position.y,
                chunkZ: chunk.position.z,
                seed: Int32(seed),
                seaLevel: seaLevel,
                baseHeight: baseHeight,
                heightVariation: heightVariation,
                terrainScale: terrainScale,
                detailScale: detailScale,
                caveScale: caveScale,
                caveThreshold: caveThreshold,
                chunkSize: Int32(CHUNK_SIZE)
            )
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: CHUNK_SIZE, height: CHUNK_SIZE, depth: 1)

        encoder.setComputePipelineState(pipeline)

        for i in 0..<count {
            let chunk = chunks[i]
            encoder.setBuffer(chunk.blockBuffer, offset: 0, index: 0)
            encoder.setBuffer(batchConfig, offset: i * configStride, index: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        for i in 0..<count {
            chunks[i].updateIsEmpty()
            chunks[i].isDirty = true
        }
    }
}
