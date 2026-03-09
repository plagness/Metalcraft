import Cocoa
import MetalKit

class GameViewController: NSViewController {

    let device: MTLDevice
    var metalView: MetalView!
    var renderer: Renderer!
    var inputManager: InputManager!
    private var renderTimer: Timer?  // Explicit timer — MTKView's internal CVDisplayLink unreliable

    init(device: MTLDevice) {
        self.device = device
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func loadView() {
        metalView = MetalView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), device: device)
        metalView.colorPixelFormat = .bgra8Unorm_srgb
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.sampleCount = 1
        metalView.preferredFramesPerSecond = 60
        metalView.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalView.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0)
        metalView.autoResizeDrawable = true
        metalView.framebufferOnly = false

        // Disable MTKView's internal timer — we drive rendering via CVDisplayLink
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false

        self.view = metalView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        inputManager = InputManager()
        metalView.inputManager = inputManager

        do {
            renderer = try Renderer(device: device, view: metalView, inputManager: inputManager)
            metalView.delegate = renderer
        } catch {
            fatalError("Failed to create renderer: \(error)")
        }

        metalView.window?.makeFirstResponder(metalView)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        metalView.window?.makeFirstResponder(metalView)

        // Notify renderer of initial size
        let size = metalView.drawableSize
        renderer.mtkView(metalView, drawableSizeWillChange: size)

        // Use Timer to drive rendering since MTKView's internal CVDisplayLink isn't firing
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.metalView.draw()
        }
        RunLoop.current.add(renderTimer!, forMode: .common)
    }

    deinit {
        renderTimer?.invalidate()
    }
}
