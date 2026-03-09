import MetalKit
import simd

/// Maximum number of in-flight frames for triple buffering.
private let maxFramesInFlight = 3
private let maxLights = 128
private let maxParticles = 8192

/// Main renderer — drives the entire render loop via MTKViewDelegate.
/// Uses a two-pass deferred pipeline optimized for Apple Silicon TBDR:
///  Pass 1: G-buffer fill (output to memoryless textures — tile memory only)
///  Pass 2: Deferred lighting (reads G-buffer from textures, applies PBR + 100+ lights)
///  Then: Forward transparency (water, particles) with alpha blending
class Renderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let inputManager: InputManager

    // MARK: - Pipeline States
    private var gbufferPipeline: MTLRenderPipelineState!
    private var lightingPipeline: MTLRenderPipelineState!
    private var waterPipeline: MTLRenderPipelineState!
    private var particlePipeline: MTLRenderPipelineState!
    private var compositePipeline: MTLRenderPipelineState!

    // MARK: - Compute Pipelines
    private var particleSimulatePipeline: MTLComputePipelineState!
    private var bloomExtractPipeline: MTLComputePipelineState!
    private var bloomDownsamplePipeline: MTLComputePipelineState!
    private var bloomUpsamplePipeline: MTLComputePipelineState!

    // MARK: - Depth States
    private var depthStateReadWrite: MTLDepthStencilState!
    private var depthStateReadOnly: MTLDepthStencilState!
    private var depthStateDisabled: MTLDepthStencilState!

    // MARK: - G-Buffer Textures (memoryless on Apple Silicon — tile memory only!)
    private var albedoMetallicTex: MTLTexture!
    private var normalRoughnessTex: MTLTexture!
    private var emissionAOTex: MTLTexture!
    private var depthTexture: MTLTexture!
    private var hdrTexture: MTLTexture!        // HDR lit result
    private var bloomTextures: [MTLTexture] = []
    private var currentDrawableSize: CGSize = .zero

    // MARK: - Triple Buffering
    private let frameSemaphore = DispatchSemaphore(value: maxFramesInFlight)
    private var uniformBuffers: [MTLBuffer] = []
    private var lightBuffers: [MTLBuffer] = []
    private var currentFrameIndex: Int = 0

    // MARK: - Camera & Time
    let camera = CameraSystem()
    var time = TimeState()

    // MARK: - Voxel World
    let chunkManager: ChunkManager
    let debugOverlay: DebugOverlay

    // MARK: - Lights
    private var lights: [LightData] = []

    // MARK: - Water Meshing
    private let waterMesher: WaterMesher

    // MARK: - Particles (single buffer — GPU compute is the only writer,
    // Metal auto-tracks hazards between command buffers in the same queue)
    private var particleBuffer: MTLBuffer!

    // MARK: - Chunk Info (per-chunk world origin, indexed by baseInstance → [[instance_id]])
    private var chunkInfoBuffer: MTLBuffer!

    // MARK: - Indirect Command Buffer (ICB)
    private var indirectCommandBuffer: MTLIndirectCommandBuffer!
    private var lastEncodedVersion: UInt64 = 0
    private var currentICBDrawCount: Int = 0

    // MARK: - Debug
    private var frameCounter: UInt32 = 0

    // MARK: - Init

    init(device: MTLDevice, view: MTKView, inputManager: InputManager) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.inputManager = inputManager
        self.chunkManager = ChunkManager(device: device, seed: 42)
        self.debugOverlay = DebugOverlay(device: device)
        self.waterMesher = WaterMesher(device: device)
        super.init()

        try buildPipelines(view: view)
        buildBuffers()
        setupLights()

        camera.position = SIMD3<Float>(0, 60, 0)
    }

    // MARK: - Pipeline Setup

    private func buildPipelines(view: MTKView) throws {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.noDefaultLibrary
        }

        // ---- G-Buffer Fill Pipeline (single-pass deferred: 4 color attachments) ----
        let gbufferDesc = MTLRenderPipelineDescriptor()
        gbufferDesc.label = "G-Buffer Fill"
        gbufferDesc.vertexFunction = library.makeFunction(name: "gbuffer_vertex")
        gbufferDesc.fragmentFunction = library.makeFunction(name: "gbuffer_fragment")
        gbufferDesc.colorAttachments[0].pixelFormat = .rgba8Unorm      // Albedo + Metallic
        gbufferDesc.colorAttachments[1].pixelFormat = .rgba8Unorm      // Normal + Roughness
        gbufferDesc.colorAttachments[2].pixelFormat = .rgba16Float     // Emission + Depth (16F for depth precision)
        gbufferDesc.colorAttachments[3].pixelFormat = .rgba16Float     // HDR (not written by G-buffer)
        gbufferDesc.colorAttachments[3].writeMask = []                 // Don't write to HDR during G-buffer fill
        gbufferDesc.depthAttachmentPixelFormat = .depth32Float
        gbufferPipeline = try device.makeRenderPipelineState(descriptor: gbufferDesc)

        // ---- Deferred Lighting Pipeline (same render pass, reads G-buffer via [[color(n)]]) ----
        let lightingDesc = MTLRenderPipelineDescriptor()
        lightingDesc.label = "Deferred Lighting"
        lightingDesc.vertexFunction = library.makeFunction(name: "deferred_lighting_vertex")
        lightingDesc.fragmentFunction = library.makeFunction(name: "deferred_lighting_fragment")
        lightingDesc.colorAttachments[0].pixelFormat = .rgba8Unorm     // G-buffer read-only
        lightingDesc.colorAttachments[0].writeMask = []
        lightingDesc.colorAttachments[1].pixelFormat = .rgba8Unorm     // G-buffer read-only
        lightingDesc.colorAttachments[1].writeMask = []
        lightingDesc.colorAttachments[2].pixelFormat = .rgba16Float    // G-buffer read-only
        lightingDesc.colorAttachments[2].writeMask = []
        lightingDesc.colorAttachments[3].pixelFormat = .rgba16Float    // HDR output
        lightingDesc.depthAttachmentPixelFormat = .depth32Float
        lightingPipeline = try device.makeRenderPipelineState(descriptor: lightingDesc)

        // ---- Water Pipeline (forward transparency) ----
        let waterDesc = MTLRenderPipelineDescriptor()
        waterDesc.label = "Water"
        waterDesc.vertexFunction = library.makeFunction(name: "water_vertex")
        waterDesc.fragmentFunction = library.makeFunction(name: "water_fragment")
        waterDesc.colorAttachments[0].pixelFormat = .rgba16Float
        waterDesc.colorAttachments[0].isBlendingEnabled = true
        waterDesc.colorAttachments[0].rgbBlendOperation = .add
        waterDesc.colorAttachments[0].alphaBlendOperation = .add
        waterDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        waterDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        waterDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        waterDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        waterDesc.depthAttachmentPixelFormat = .depth32Float
        waterPipeline = try device.makeRenderPipelineState(descriptor: waterDesc)

        // ---- Particle Pipeline (forward transparency) ----
        let particleDesc = MTLRenderPipelineDescriptor()
        particleDesc.label = "Particles"
        particleDesc.vertexFunction = library.makeFunction(name: "particle_vertex")
        particleDesc.fragmentFunction = library.makeFunction(name: "particle_fragment")
        particleDesc.colorAttachments[0].pixelFormat = .rgba16Float
        particleDesc.colorAttachments[0].isBlendingEnabled = true
        particleDesc.colorAttachments[0].rgbBlendOperation = .add
        particleDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        particleDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        particleDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        particleDesc.depthAttachmentPixelFormat = .depth32Float
        particlePipeline = try device.makeRenderPipelineState(descriptor: particleDesc)

        // ---- Final Composite Pipeline ----
        let compositeDesc = MTLRenderPipelineDescriptor()
        compositeDesc.label = "Final Composite"
        compositeDesc.vertexFunction = library.makeFunction(name: "composite_vertex")
        compositeDesc.fragmentFunction = library.makeFunction(name: "composite_fragment")
        compositeDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        compositePipeline = try device.makeRenderPipelineState(descriptor: compositeDesc)

        // ---- Compute Pipelines ----
        particleSimulatePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "particle_simulate")!)
        bloomExtractPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "bloom_extract")!)
        bloomDownsamplePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "bloom_downsample")!)
        bloomUpsamplePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "bloom_upsample")!)

        // ---- Depth States ----
        let dsReadWrite = MTLDepthStencilDescriptor()
        dsReadWrite.depthCompareFunction = .less
        dsReadWrite.isDepthWriteEnabled = true
        depthStateReadWrite = device.makeDepthStencilState(descriptor: dsReadWrite)

        let dsReadOnly = MTLDepthStencilDescriptor()
        dsReadOnly.depthCompareFunction = .less
        dsReadOnly.isDepthWriteEnabled = false
        depthStateReadOnly = device.makeDepthStencilState(descriptor: dsReadOnly)

        let dsDisabled = MTLDepthStencilDescriptor()
        dsDisabled.depthCompareFunction = .always
        dsDisabled.isDepthWriteEnabled = false
        depthStateDisabled = device.makeDepthStencilState(descriptor: dsDisabled)
    }

    private func buildBuffers() {
        for i in 0..<maxFramesInFlight {
            // Uniform buffers (storageModeShared — zero-copy UMA)
            guard let uBuf = device.makeBuffer(
                length: MemoryLayout<FrameUniforms>.stride,
                options: .storageModeShared
            ) else { fatalError("Failed to create uniform buffer \(i)") }
            uBuf.label = "Uniforms \(i)"
            uniformBuffers.append(uBuf)

            // Light buffers
            guard let lBuf = device.makeBuffer(
                length: MemoryLayout<LightData>.stride * maxLights,
                options: .storageModeShared
            ) else { fatalError("Failed to create light buffer \(i)") }
            lBuf.label = "Lights \(i)"
            lightBuffers.append(lBuf)

        }

        // Chunk info buffer — one ChunkInfo per renderable chunk (world origin for vertex shader)
        let maxChunks = chunkManager.maxRenderChunks
        guard let ciBuf = device.makeBuffer(
            length: MemoryLayout<ChunkInfo>.stride * maxChunks,
            options: .storageModeShared
        ) else { fatalError("Failed to create chunk info buffer") }
        ciBuf.label = "ChunkInfo"
        chunkInfoBuffer = ciBuf

        // Indirect Command Buffer — one executeCommandsInBuffer replaces 4500 drawIndexedPrimitives
        let icbDesc = MTLIndirectCommandBufferDescriptor()
        icbDesc.commandTypes = .drawIndexed
        icbDesc.inheritBuffers = true        // inherits vertex buffers from render encoder
        icbDesc.inheritPipelineState = true  // inherits pipeline state from render encoder
        icbDesc.maxVertexBufferBindCount = 0
        icbDesc.maxFragmentBufferBindCount = 0
        guard let icb = device.makeIndirectCommandBuffer(
            descriptor: icbDesc,
            maxCommandCount: maxChunks,
            options: .storageModeShared
        ) else { fatalError("Failed to create ICB") }
        icb.label = "ChunkICB"
        indirectCommandBuffer = icb

        // Single particle buffer — GPU compute writes, GPU render reads.
        // No triple-buffering needed: CPU never touches this after init,
        // and Metal tracks read/write hazards between command buffers automatically.
        guard let pBuf = device.makeBuffer(
            length: 48 * maxParticles,
            options: .storageModeShared
        ) else { fatalError("Failed to create particle buffer") }
        pBuf.label = "Particles"
        memset(pBuf.contents(), 0, 48 * maxParticles)
        particleBuffer = pBuf
    }

    // MARK: - Lights Setup

    private func setupLights() {
        lights.removeAll()

        // 16 colored point lights — enough for visual demo, easy on PBR per-pixel cost
        for i in 0..<16 {
            var light = LightData()
            let angle = Float(i) * (2.0 * .pi / 16.0)
            let radius = Float(25 + (i % 4) * 12)
            let height = Float(45 + (i % 3) * 8)

            light.position = SIMD3<Float>(
                cos(angle) * radius,
                height,
                sin(angle) * radius
            )
            light.radius = 20.0

            let hue = Float(i) / 16.0
            light.color = hueToRGB(hue)
            light.intensity = 1.2 + Float(i % 3) * 0.4
            light.direction = SIMD3<Float>(0, -1, 0)
            light.innerConeAngle = 0
            light.outerConeAngle = 0
            light.type = UInt32(LightTypePoint.rawValue)
            light.castsShadow = 0
            light._padding = 0

            lights.append(light)
        }
    }

    private func hueToRGB(_ hue: Float) -> SIMD3<Float> {
        let h = hue * 6.0
        let x = 1.0 - abs(h.truncatingRemainder(dividingBy: 2.0) - 1.0)
        switch Int(h) % 6 {
        case 0: return SIMD3<Float>(1, x, 0)
        case 1: return SIMD3<Float>(x, 1, 0)
        case 2: return SIMD3<Float>(0, 1, x)
        case 3: return SIMD3<Float>(0, x, 1)
        case 4: return SIMD3<Float>(x, 0, 1)
        default: return SIMD3<Float>(1, 0, x)
        }
    }

    // MARK: - Texture Creation

    private func buildOffscreenTextures(size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        let w = Int(size.width)
        let h = Int(size.height)

        func makeTex(_ format: MTLPixelFormat, width: Int, height: Int,
                     usage: MTLTextureUsage, label: String) -> MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: width, height: height, mipmapped: false)
            desc.usage = usage
            desc.storageMode = .private
            let tex = device.makeTexture(descriptor: desc)!
            tex.label = label
            return tex
        }

        // G-buffer — storeAction=.dontCare keeps data in tile memory on TBDR.
        // Use .private storage; the driver knows not to write back thanks to .dontCare.
        albedoMetallicTex = makeTex(.rgba8Unorm, width: w, height: h,
                                     usage: .renderTarget, label: "G-Buffer Albedo")
        normalRoughnessTex = makeTex(.rgba8Unorm, width: w, height: h,
                                      usage: .renderTarget, label: "G-Buffer Normal")
        emissionAOTex = makeTex(.rgba16Float, width: w, height: h,
                                 usage: .renderTarget, label: "G-Buffer Emission+Depth")
        depthTexture = makeTex(.depth32Float, width: w, height: h,
                                usage: [.renderTarget, .shaderRead], label: "Depth")

        // HDR at native resolution
        hdrTexture = makeTex(.rgba16Float, width: w, height: h,
                              usage: [.renderTarget, .shaderRead, .shaderWrite], label: "HDR")

        // Bloom chain (minimal — just need one texture for composite shader binding)
        bloomTextures.removeAll()
        var bw = w / 2, bh = h / 2
        for i in 0..<4 {
            bloomTextures.append(makeTex(.rgba16Float, width: max(1, bw), height: max(1, bh),
                                          usage: [.shaderRead, .shaderWrite], label: "Bloom \(i)"))
            bw /= 2; bh /= 2
        }

        currentDrawableSize = size
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspectRatio = Float(size.width / size.height)
        buildOffscreenTextures(size: size)
    }

    private var gpuWaitAccumMs: Float = 0
    private var gpuWaitFrames: Int = 0

    func draw(in view: MTKView) {
        let waitStart = CACurrentMediaTime()
        frameSemaphore.wait()
        let waitMs = Float((CACurrentMediaTime() - waitStart) * 1000.0)
        gpuWaitAccumMs += waitMs
        gpuWaitFrames += 1
        frameCounter += 1

        // Ensure textures exist
        let drawableSize = view.drawableSize
        if currentDrawableSize != drawableSize || hdrTexture == nil {
            buildOffscreenTextures(size: drawableSize)
        }

        time.update()
        camera.update(input: inputManager, deltaTime: time.deltaTime)

        let frustum = Frustum(viewProjection: camera.viewProjectionMatrix)
        chunkManager.update(cameraPosition: camera.position, cameraForward: camera.forward, frustum: frustum)

        // Invalidate water meshes for chunks that were re-meshed
        for pos in chunkManager.recentlyRemeshedPositions {
            waterMesher.invalidate(position: pos)
        }

        let bufferIndex = currentFrameIndex % maxFramesInFlight
        currentFrameIndex += 1

        // Animate lights (orbit around camera)
        animateLights()

        // Write uniforms (native resolution)
        var uniforms = camera.buildUniforms(
            screenWidth: Float(drawableSize.width),
            screenHeight: Float(drawableSize.height),
            time: time.totalTime,
            frameIndex: frameCounter
        )
        uniforms.lightCount = UInt32(lights.count)

        let uniformBuffer = uniformBuffers[bufferIndex]
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<FrameUniforms>.stride)

        // Write lights
        let lightBuffer = lightBuffers[bufferIndex]
        lights.withUnsafeBufferPointer { ptr in
            memcpy(lightBuffer.contents(), ptr.baseAddress!, MemoryLayout<LightData>.stride * lights.count)
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable else {
            frameSemaphore.signal()
            return
        }
        commandBuffer.label = "Frame \(frameCounter)"

        // === SINGLE-PASS DEFERRED: G-Buffer Fill + Lighting in ONE render pass ===
        // On Apple Silicon TBDR, both draws share tile memory. G-buffer NEVER hits DRAM.
        // The lighting pass reads G-buffer via [[color(n)]] (programmable blending).
        let deferredPassDesc = MTLRenderPassDescriptor()

        // G-buffer attachments — memoryless, storeAction = .dontCare (tile memory only!)
        deferredPassDesc.colorAttachments[0].texture = albedoMetallicTex
        deferredPassDesc.colorAttachments[0].loadAction = .clear
        deferredPassDesc.colorAttachments[0].storeAction = .dontCare  // Never leaves tile memory
        deferredPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        deferredPassDesc.colorAttachments[1].texture = normalRoughnessTex
        deferredPassDesc.colorAttachments[1].loadAction = .clear
        deferredPassDesc.colorAttachments[1].storeAction = .dontCare
        deferredPassDesc.colorAttachments[1].clearColor = MTLClearColor(red: 0.5, green: 0.5, blue: 1, alpha: 0)

        deferredPassDesc.colorAttachments[2].texture = emissionAOTex
        deferredPassDesc.colorAttachments[2].loadAction = .clear
        deferredPassDesc.colorAttachments[2].storeAction = .dontCare
        deferredPassDesc.colorAttachments[2].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // HDR output — this one DOES get stored to DRAM
        deferredPassDesc.colorAttachments[3].texture = hdrTexture
        deferredPassDesc.colorAttachments[3].loadAction = .dontCare
        deferredPassDesc.colorAttachments[3].storeAction = .store

        deferredPassDesc.depthAttachment.texture = depthTexture
        deferredPassDesc.depthAttachment.loadAction = .clear
        deferredPassDesc.depthAttachment.storeAction = .store  // Needed for water/transparency
        deferredPassDesc.depthAttachment.clearDepth = 1.0

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: deferredPassDesc) {
            // --- Draw 1: G-Buffer Fill ---
            encoder.label = "Single-Pass Deferred"
            encoder.setRenderPipelineState(gbufferPipeline)
            encoder.setDepthStencilState(depthStateReadWrite)
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.back)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

            // Fill ChunkInfo buffer (world origins for each renderable chunk)
            let ciPtr = chunkInfoBuffer.contents().bindMemory(to: ChunkInfo.self, capacity: chunkManager.maxRenderChunks)
            let chunkSize = Float(CHUNK_SIZE)
            for (i, chunk) in chunkManager.renderableChunks.enumerated() {
                ciPtr[i] = ChunkInfo(
                    worldOrigin: SIMD3<Float>(
                        Float(chunk.position.x) * chunkSize,
                        Float(chunk.position.y) * chunkSize,
                        Float(chunk.position.z) * chunkSize
                    ),
                    _padding: 0
                )
            }

            // Bind mega-buffers ONCE — inherited by ICB commands
            let allocator = chunkManager.meshAllocator
            encoder.setVertexBuffer(allocator.vertexBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))
            encoder.setVertexBuffer(chunkInfoBuffer, offset: 0, index: Int(BufferIndexChunkInfo.rawValue))

            // Encode ICB (no-op if renderableList hasn't changed)
            encodeICBIfNeeded()

            // Execute all chunk draws in one call!
            if currentICBDrawCount > 0 {
                encoder.executeCommandsInBuffer(indirectCommandBuffer, range: 0..<currentICBDrawCount)
            }

            // --- Draw 2: Deferred Lighting (reads G-buffer from tile memory) ---
            encoder.setRenderPipelineState(lightingPipeline)
            encoder.setDepthStencilState(depthStateDisabled)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            encoder.setFragmentBuffer(lightBuffer, offset: 0, index: Int(BufferIndexLights.rawValue))
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            encoder.endEncoding()
        }

        // === PASS 3: Final Composite → Drawable ===
        let compositePassDesc = MTLRenderPassDescriptor()
        compositePassDesc.colorAttachments[0].texture = drawable.texture
        compositePassDesc.colorAttachments[0].loadAction = .dontCare
        compositePassDesc.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: compositePassDesc) {
            encoder.label = "Final Composite"
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setDepthStencilState(depthStateDisabled)
            encoder.setFragmentTexture(hdrTexture, index: 0) // HDR at native res
            encoder.setFragmentTexture(bloomTextures[0], index: 1) // Bloom glow
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        // Present
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }
        commandBuffer.commit()

        // Debug overlay
        if frameCounter % 30 == 0 {
            let avgWait = gpuWaitFrames > 0 ? gpuWaitAccumMs / Float(gpuWaitFrames) : 0
            let stats = String(format: "FPS: %.0f | Chunks: %d/%d | Tris: %dK | Verts: %dK | GPUwait: %.1fms | Pos: %.0f,%.0f,%.0f\n",
                  time.smoothFPS,
                  chunkManager.renderedChunkCount,
                  chunkManager.loadedChunkCount,
                  chunkManager.totalTriangles / 1000,
                  chunkManager.totalVertices / 1000,
                  avgWait,
                  camera.position.x, camera.position.y, camera.position.z)
            try? stats.write(toFile: "/tmp/voxel_stats.txt", atomically: true, encoding: .utf8)
            gpuWaitAccumMs = 0
            gpuWaitFrames = 0
        }
    }

    // MARK: - Light Animation

    private func animateLights() {
        let t = time.totalTime
        for i in 0..<lights.count {
            let angle = Float(i) * (2.0 * .pi / 16.0) + t * 0.15
            let radius = Float(25 + (i % 4) * 12)
            let baseHeight = Float(8 + (i % 3) * 5) // relative to camera

            lights[i].position = camera.position + SIMD3<Float>(
                cos(angle) * radius,
                baseHeight + sin(t * 0.4 + Float(i)) * 2.0,
                sin(angle) * radius
            )

            lights[i].intensity = 1.0 + Float(i % 3) * 0.3 + sin(t * 1.2 + Float(i) * 0.7) * 0.1
        }
    }

    // MARK: - ICB Encoding

    /// Encode the Indirect Command Buffer from the current renderableChunks.
    /// No-op if renderableListVersion hasn't changed — amortized cost ~0.07ms/frame.
    private func encodeICBIfNeeded() {
        let version = chunkManager.renderableListVersion
        guard version != lastEncodedVersion else { return }

        let allocator = chunkManager.meshAllocator
        let vStride = MemoryLayout<PackedVoxelVertex>.stride
        let chunks = chunkManager.renderableChunks
        let maxCmds = chunkManager.maxRenderChunks
        var drawIdx = 0

        for i in 0..<chunks.count {
            guard drawIdx < maxCmds else { break }
            let chunk = chunks[i]
            guard let alloc = chunk.meshAllocation else { continue }

            let cmd = indirectCommandBuffer.indirectRenderCommandAt(drawIdx)
            cmd.drawIndexedPrimitives(
                .triangle,
                indexCount: alloc.indexCount,
                indexType: .uint32,
                indexBuffer: allocator.indexBuffer,
                indexBufferOffset: alloc.indexOffset,
                instanceCount: 1,
                baseVertex: alloc.vertexOffset / vStride,
                baseInstance: i
            )
            drawIdx += 1
        }

        // Reset unused slots from previous encoding
        let resetEnd = min(currentICBDrawCount, maxCmds)
        if drawIdx < resetEnd {
            for i in drawIdx..<resetEnd {
                indirectCommandBuffer.indirectRenderCommandAt(i).reset()
            }
        }

        currentICBDrawCount = drawIdx
        lastEncodedVersion = version
    }
}

// MARK: - Errors

enum RendererError: Error {
    case noDefaultLibrary
    case pipelineCreationFailed(String)
}

// MARK: - Particle Config (matches Metal struct)

struct ParticleConfig {
    var emitterPosition: SIMD3<Float>
    var deltaTime: Float
    var gravity: SIMD3<Float>
    var spawnRate: Float
    var windDirection: SIMD3<Float>
    var windStrength: Float
    var emitterRadius: Float
    var maxParticles: UInt32
    var frameIndex: UInt32
    var _padding: Float
}
