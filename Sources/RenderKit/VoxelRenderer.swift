import CoreGraphics
import Foundation
import MetalKit
import QuartzCore
import WorldKit

private final class ShaderBundleToken {}

private struct MeshVertex {
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
}

private struct InstanceData {
    let translation: SIMD3<Float>
    let color: SIMD4<Float>
}

private struct FrameUniforms {
    let viewProjection: simd_float4x4
    let lightDirection: SIMD3<Float>
    let padding: Float
}

public final class VoxelRenderer: NSObject, MTKViewDelegate {
    public private(set) var renderDiagnostics: String = "Preparing Metal renderer"

    private let world: WorldSnapshot
    private var viewportSize: CGSize = CGSize(width: 1, height: 1)
    private var startTime = CACurrentMediaTime()

    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var instanceBuffer: MTLBuffer?
    private var indexCount = 0
    private var instanceCount = 0

    public init(world: WorldSnapshot) {
        self.world = world
        super.init()
    }

    @MainActor
    public func makeView(frame: CGRect = .zero) -> MTKView {
        let view = MTKView(frame: frame, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.04, green: 0.07, blue: 0.10, alpha: 1.0)
        view.preferredFramesPerSecond = 60
        view.sampleCount = 1
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        configure(view: view)
        return view
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    public func draw(in view: MTKView) {
        guard
            let device = view.device,
            let pipelineState,
            let commandQueue,
            let depthState,
            let vertexBuffer,
            let indexBuffer,
            let instanceBuffer,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            return
        }

        let time = Float(CACurrentMediaTime() - startTime)
        let aspect = max(Float(viewportSize.width / max(viewportSize.height, 1)), 1.0)
        let center = SIMD3(Float(world.size.x) * 0.5, Float(world.size.y) * 0.32, Float(world.size.z) * 0.5)
        let radius = Float(max(world.size.x, world.size.z)) * 0.72
        let eye = center + SIMD3(cos(time * 0.23) * radius, 10.5 + sin(time * 0.17) * 2.4, sin(time * 0.23) * radius)

        let viewMatrix = Float4x4.lookAt(eye: eye, center: center, up: SIMD3(0, 1, 0))
        let projection = Float4x4.perspective(fovY: 0.95, aspect: aspect, nearZ: 0.1, farZ: 250)
        var uniforms = FrameUniforms(
            viewProjection: projection * viewMatrix,
            lightDirection: simd_normalize(SIMD3<Float>(0.6, 0.9, 0.4)),
            padding: 0
        )

        guard let uniformBuffer = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<FrameUniforms>.stride) else {
            return
        }

        let commandBuffer = commandQueue.makeCommandBuffer()
        let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        encoder?.label = "Voxel World Pass"
        encoder?.setRenderPipelineState(pipelineState)
        encoder?.setDepthStencilState(depthState)
        encoder?.setCullMode(.back)
        encoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder?.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder?.setVertexBuffer(uniformBuffer, offset: 0, index: 2)
        encoder?.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: instanceCount
        )
        encoder?.endEncoding()

        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }

    @MainActor
    private func configure(view: MTKView) {
        viewportSize = view.drawableSize
        view.delegate = self

        guard let device = view.device else {
            renderDiagnostics = "Metal unavailable on this machine"
            return
        }

        do {
            try buildResources(device: device, view: view)
            renderDiagnostics = "MetalKit viewport online • \(instanceCount) visible blocks"
        } catch {
            renderDiagnostics = "Renderer bootstrap failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func buildResources(device: MTLDevice, view: MTKView) throws {
        let bundle = Bundle(for: ShaderBundleToken.self)
        let library = try device.makeDefaultLibrary(bundle: bundle)
        let vertexFunction = library.makeFunction(name: "voxel_vertex")
        let fragmentFunction = library.makeFunction(name: "voxel_fragment")

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Voxel Pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.isDepthWriteEnabled = true
        depthDescriptor.depthCompareFunction = .less
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
        commandQueue = device.makeCommandQueue()

        let (vertices, indices) = Self.makeCubeMesh()
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<MeshVertex>.stride)
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride)
        indexCount = indices.count

        let instances = world.solidBlocks.map { block in
            InstanceData(translation: block.position.vector, color: block.material.color)
        }
        instanceBuffer = device.makeBuffer(bytes: instances, length: instances.count * MemoryLayout<InstanceData>.stride)
        instanceCount = instances.count
    }

    private static func makeCubeMesh() -> ([MeshVertex], [UInt16]) {
        let vertices: [MeshVertex] = [
            MeshVertex(position: SIMD3(0, 0, 1), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3(1, 0, 1), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3(1, 1, 1), normal: SIMD3(0, 0, 1)),
            MeshVertex(position: SIMD3(0, 1, 1), normal: SIMD3(0, 0, 1)),

            MeshVertex(position: SIMD3(1, 0, 0), normal: SIMD3(0, 0, -1)),
            MeshVertex(position: SIMD3(0, 0, 0), normal: SIMD3(0, 0, -1)),
            MeshVertex(position: SIMD3(0, 1, 0), normal: SIMD3(0, 0, -1)),
            MeshVertex(position: SIMD3(1, 1, 0), normal: SIMD3(0, 0, -1)),

            MeshVertex(position: SIMD3(0, 0, 0), normal: SIMD3(-1, 0, 0)),
            MeshVertex(position: SIMD3(0, 0, 1), normal: SIMD3(-1, 0, 0)),
            MeshVertex(position: SIMD3(0, 1, 1), normal: SIMD3(-1, 0, 0)),
            MeshVertex(position: SIMD3(0, 1, 0), normal: SIMD3(-1, 0, 0)),

            MeshVertex(position: SIMD3(1, 0, 1), normal: SIMD3(1, 0, 0)),
            MeshVertex(position: SIMD3(1, 0, 0), normal: SIMD3(1, 0, 0)),
            MeshVertex(position: SIMD3(1, 1, 0), normal: SIMD3(1, 0, 0)),
            MeshVertex(position: SIMD3(1, 1, 1), normal: SIMD3(1, 0, 0)),

            MeshVertex(position: SIMD3(0, 1, 1), normal: SIMD3(0, 1, 0)),
            MeshVertex(position: SIMD3(1, 1, 1), normal: SIMD3(0, 1, 0)),
            MeshVertex(position: SIMD3(1, 1, 0), normal: SIMD3(0, 1, 0)),
            MeshVertex(position: SIMD3(0, 1, 0), normal: SIMD3(0, 1, 0)),

            MeshVertex(position: SIMD3(0, 0, 0), normal: SIMD3(0, -1, 0)),
            MeshVertex(position: SIMD3(1, 0, 0), normal: SIMD3(0, -1, 0)),
            MeshVertex(position: SIMD3(1, 0, 1), normal: SIMD3(0, -1, 0)),
            MeshVertex(position: SIMD3(0, 0, 1), normal: SIMD3(0, -1, 0)),
        ]

        let indices: [UInt16] = [
            0, 1, 2, 0, 2, 3,
            4, 5, 6, 4, 6, 7,
            8, 9, 10, 8, 10, 11,
            12, 13, 14, 12, 14, 15,
            16, 17, 18, 16, 18, 19,
            20, 21, 22, 20, 22, 23,
        ]

        return (vertices, indices)
    }
}
