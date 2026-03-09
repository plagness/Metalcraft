import Cocoa
import Metal
import CoreText
import CoreGraphics

/// Renders debug text (FPS, camera position, etc.) by rasterizing to a texture.
class DebugOverlay {

    private let device: MTLDevice
    private var textTexture: MTLTexture?
    private let textureWidth = 512
    private let textureHeight = 128

    init(device: MTLDevice) {
        self.device = device
    }

    /// Updates the debug text texture. Call once per frame.
    func update(fps: Float, cameraPos: SIMD3<Float>, frameIndex: UInt32) {
        let text = String(format: """
            FPS: %.0f
            Pos: %.1f, %.1f, %.1f
            Frame: %d
            """, fps, cameraPos.x, cameraPos.y, cameraPos.z, frameIndex)

        textTexture = renderTextToTexture(text)
    }

    /// Returns the current debug text texture for rendering as an overlay.
    var texture: MTLTexture? { textTexture }

    // MARK: - Text Rendering

    private func renderTextToTexture(_ text: String) -> MTLTexture? {
        let width = textureWidth
        let height = textureHeight

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Clear with semi-transparent black background
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor(red: 0.0, green: 1.0, blue: 0.4, alpha: 1.0)
        ]
        // Flip context for correct text orientation
        context.textMatrix = .identity
        context.translateBy(x: 8, y: CGFloat(height) - 20)
        context.scaleBy(x: 1, y: -1)

        // Draw each line
        let lines = text.components(separatedBy: "\n")
        for (i, lineText) in lines.enumerated() {
            let lineAttrString = NSAttributedString(string: lineText, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(lineAttrString)
            context.textPosition = CGPoint(x: 0, y: CGFloat(i) * 18)
            CTLineDraw(ctLine, context)
        }

        guard let imageData = context.data else { return nil }

        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDesc.usage = .shaderRead
        textureDesc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: textureDesc) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: imageData,
            bytesPerRow: width * 4
        )

        return texture
    }
}
