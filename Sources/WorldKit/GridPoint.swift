import Foundation
import simd

public struct GridPoint: Hashable, Codable, Sendable, Identifiable {
    public let x: Int
    public let y: Int
    public let z: Int

    public var id: String {
        "\(x):\(y):\(z)"
    }

    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var vector: SIMD3<Float> {
        SIMD3(Float(x), Float(y), Float(z))
    }
}
