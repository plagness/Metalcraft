import simd

/// Block type identifiers. UInt16 allows up to 65,536 types.
enum BlockType: UInt16 {
    case air        = 0
    case stone      = 1
    case dirt       = 2
    case grass      = 3
    case sand       = 4
    case water      = 5
    case wood       = 6
    case leaves     = 7
    case snow       = 8
    case gravel     = 9
    case ore        = 10
    case glass      = 11
    case lamp       = 12
    case metal      = 13
    case neonRed    = 14
    case neonBlue   = 15
    case neonGreen  = 16
    case tallGrass  = 17
    case darkGrass  = 18
    case cactus     = 19
    case clay       = 20
    case pineLeaves = 21
    case birchWood  = 22
    case redFlower  = 23
    case deadBush   = 24
    case ice        = 25
    case mossy      = 26
}

/// Properties for each block type.
struct BlockProperties {
    let color: SIMD4<Float>
    let isTransparent: Bool
    let isEmissive: Bool
    let roughness: Float
    let metallic: Float

    static let air = BlockProperties(color: .zero, isTransparent: true, isEmissive: false, roughness: 0, metallic: 0)
}

/// Registry of all block types and their properties.
struct BlockRegistry {

    static let properties: [BlockType: BlockProperties] = [
        .air:       .air,
        .stone:     BlockProperties(color: SIMD4<Float>(0.50, 0.50, 0.52, 1), isTransparent: false, isEmissive: false, roughness: 0.85, metallic: 0.0),
        .dirt:      BlockProperties(color: SIMD4<Float>(0.45, 0.32, 0.22, 1), isTransparent: false, isEmissive: false, roughness: 0.95, metallic: 0.0),
        .grass:     BlockProperties(color: SIMD4<Float>(0.30, 0.55, 0.25, 1), isTransparent: false, isEmissive: false, roughness: 0.90, metallic: 0.0),
        .sand:      BlockProperties(color: SIMD4<Float>(0.82, 0.75, 0.55, 1), isTransparent: false, isEmissive: false, roughness: 0.95, metallic: 0.0),
        .water:     BlockProperties(color: SIMD4<Float>(0.20, 0.40, 0.75, 0.6), isTransparent: true, isEmissive: false, roughness: 0.10, metallic: 0.0),
        .wood:      BlockProperties(color: SIMD4<Float>(0.55, 0.35, 0.18, 1), isTransparent: false, isEmissive: false, roughness: 0.80, metallic: 0.0),
        .leaves:    BlockProperties(color: SIMD4<Float>(0.20, 0.50, 0.15, 0.85), isTransparent: true, isEmissive: false, roughness: 0.90, metallic: 0.0),
        .snow:      BlockProperties(color: SIMD4<Float>(0.92, 0.93, 0.96, 1), isTransparent: false, isEmissive: false, roughness: 0.70, metallic: 0.0),
        .gravel:    BlockProperties(color: SIMD4<Float>(0.55, 0.53, 0.50, 1), isTransparent: false, isEmissive: false, roughness: 0.95, metallic: 0.0),
        .ore:       BlockProperties(color: SIMD4<Float>(0.45, 0.45, 0.50, 1), isTransparent: false, isEmissive: false, roughness: 0.60, metallic: 0.50),
        .glass:     BlockProperties(color: SIMD4<Float>(0.80, 0.85, 0.90, 0.3), isTransparent: true, isEmissive: false, roughness: 0.05, metallic: 0.0),
        .lamp:      BlockProperties(color: SIMD4<Float>(1.00, 0.95, 0.80, 1), isTransparent: false, isEmissive: true, roughness: 0.30, metallic: 0.0),
        .metal:     BlockProperties(color: SIMD4<Float>(0.70, 0.72, 0.75, 1), isTransparent: false, isEmissive: false, roughness: 0.30, metallic: 0.90),
        .neonRed:   BlockProperties(color: SIMD4<Float>(1.00, 0.15, 0.20, 1), isTransparent: false, isEmissive: true, roughness: 0.20, metallic: 0.0),
        .neonBlue:  BlockProperties(color: SIMD4<Float>(0.20, 0.40, 1.00, 1), isTransparent: false, isEmissive: true, roughness: 0.20, metallic: 0.0),
        .neonGreen: BlockProperties(color: SIMD4<Float>(0.20, 1.00, 0.40, 1), isTransparent: false, isEmissive: true, roughness: 0.20, metallic: 0.0),
        .tallGrass: BlockProperties(color: SIMD4<Float>(0.25, 0.55, 0.18, 1), isTransparent: true, isEmissive: false, roughness: 0.95, metallic: 0.0),
        .darkGrass: BlockProperties(color: SIMD4<Float>(0.18, 0.42, 0.15, 1), isTransparent: false, isEmissive: false, roughness: 0.90, metallic: 0.0),
        .cactus:    BlockProperties(color: SIMD4<Float>(0.15, 0.50, 0.12, 1), isTransparent: false, isEmissive: false, roughness: 0.80, metallic: 0.0),
        .clay:      BlockProperties(color: SIMD4<Float>(0.62, 0.55, 0.45, 1), isTransparent: false, isEmissive: false, roughness: 0.90, metallic: 0.0),
        .pineLeaves:BlockProperties(color: SIMD4<Float>(0.10, 0.32, 0.10, 0.85), isTransparent: true, isEmissive: false, roughness: 0.90, metallic: 0.0),
        .birchWood: BlockProperties(color: SIMD4<Float>(0.85, 0.82, 0.75, 1), isTransparent: false, isEmissive: false, roughness: 0.80, metallic: 0.0),
        .redFlower: BlockProperties(color: SIMD4<Float>(0.85, 0.15, 0.15, 1), isTransparent: true, isEmissive: false, roughness: 0.90, metallic: 0.0),
        .deadBush:  BlockProperties(color: SIMD4<Float>(0.55, 0.42, 0.25, 1), isTransparent: true, isEmissive: false, roughness: 0.95, metallic: 0.0),
        .ice:       BlockProperties(color: SIMD4<Float>(0.75, 0.85, 0.95, 0.8), isTransparent: true, isEmissive: false, roughness: 0.05, metallic: 0.0),
        .mossy:     BlockProperties(color: SIMD4<Float>(0.35, 0.48, 0.30, 1), isTransparent: false, isEmissive: false, roughness: 0.90, metallic: 0.0),
    ]

    static func getProperties(_ type: BlockType) -> BlockProperties {
        return properties[type] ?? .air
    }

    static func isOpaque(_ type: BlockType) -> Bool {
        guard let props = properties[type] else { return false }
        return !props.isTransparent && type != .air
    }

    static func isSolid(_ type: BlockType) -> Bool {
        return type != .air
    }
}
