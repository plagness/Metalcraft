import MetalKit
import SwiftUI

public struct VoxelViewport: NSViewRepresentable {
    private let renderer: VoxelRenderer

    public init(renderer: VoxelRenderer) {
        self.renderer = renderer
    }

    public func makeNSView(context: Context) -> MTKView {
        renderer.makeView()
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        _ = nsView
    }
}
