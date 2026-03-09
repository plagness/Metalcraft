import Foundation
import simd

public enum BlockMaterial: String, CaseIterable, Codable, Sendable {
    case grass
    case dirt
    case stone
    case copperOre
    case ironOre
    case coal
    case furnace
    case generator
    case battery
    case conveyor
    case cable
    case steelPlating

    public var displayName: String {
        switch self {
        case .grass: "Grass"
        case .dirt: "Dirt"
        case .stone: "Stone"
        case .copperOre: "Copper Ore"
        case .ironOre: "Iron Ore"
        case .coal: "Coal"
        case .furnace: "Arc Furnace"
        case .generator: "Steam Dynamo"
        case .battery: "Capacitor Bank"
        case .conveyor: "Conveyor"
        case .cable: "HV Cable"
        case .steelPlating: "Steel Plating"
        }
    }

    public var color: SIMD4<Float> {
        switch self {
        case .grass: SIMD4(0.31, 0.63, 0.29, 1.0)
        case .dirt: SIMD4(0.46, 0.31, 0.18, 1.0)
        case .stone: SIMD4(0.56, 0.58, 0.64, 1.0)
        case .copperOre: SIMD4(0.74, 0.44, 0.24, 1.0)
        case .ironOre: SIMD4(0.66, 0.60, 0.54, 1.0)
        case .coal: SIMD4(0.17, 0.18, 0.20, 1.0)
        case .furnace: SIMD4(0.91, 0.52, 0.20, 1.0)
        case .generator: SIMD4(0.24, 0.48, 0.78, 1.0)
        case .battery: SIMD4(0.70, 0.92, 0.30, 1.0)
        case .conveyor: SIMD4(0.62, 0.55, 0.20, 1.0)
        case .cable: SIMD4(0.95, 0.83, 0.20, 1.0)
        case .steelPlating: SIMD4(0.75, 0.80, 0.84, 1.0)
        }
    }
}

public struct VoxelBlock: Hashable, Codable, Sendable, Identifiable {
    public let position: GridPoint
    public let material: BlockMaterial

    public var id: GridPoint {
        position
    }

    public init(position: GridPoint, material: BlockMaterial) {
        self.position = position
        self.material = material
    }
}

public struct WorldSnapshot: Sendable {
    public let size: GridPoint
    public let blocks: [VoxelBlock]
    public let seed: Int

    public init(size: GridPoint, blocks: [VoxelBlock], seed: Int) {
        self.size = size
        self.blocks = blocks
        self.seed = seed
    }

    public var solidBlocks: [VoxelBlock] {
        blocks
    }

    public var materialBreakdown: [(material: BlockMaterial, count: Int)] {
        Dictionary(grouping: blocks, by: \.material)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}

public enum WorldBootstrap {
    public static func demoWorld() -> WorldSnapshot {
        let size = GridPoint(x: 24, y: 14, z: 24)
        var blocks: [VoxelBlock] = []
        blocks.reserveCapacity(3_500)

        for x in 0..<size.x {
            for z in 0..<size.z {
                let wave = sin(Float(x) * 0.38) + cos(Float(z) * 0.34)
                let height = max(3, min(7, Int(4.8 + wave)))

                for y in 0..<height {
                    let material: BlockMaterial
                    if y == height - 1 {
                        material = .grass
                    } else if y >= height - 3 {
                        material = .dirt
                    } else {
                        material = .stone
                    }

                    blocks.append(VoxelBlock(position: GridPoint(x: x, y: y, z: z), material: material))
                }
            }
        }

        let copperVein = [
            GridPoint(x: 5, y: 2, z: 7),
            GridPoint(x: 6, y: 2, z: 7),
            GridPoint(x: 7, y: 1, z: 8),
            GridPoint(x: 7, y: 2, z: 8),
            GridPoint(x: 8, y: 2, z: 9),
        ]
        let ironVein = [
            GridPoint(x: 16, y: 2, z: 14),
            GridPoint(x: 16, y: 1, z: 15),
            GridPoint(x: 17, y: 2, z: 15),
            GridPoint(x: 18, y: 2, z: 16),
            GridPoint(x: 17, y: 3, z: 16),
        ]
        let coalPocket = [
            GridPoint(x: 11, y: 1, z: 11),
            GridPoint(x: 12, y: 2, z: 11),
            GridPoint(x: 12, y: 1, z: 12),
        ]

        blocks.append(contentsOf: copperVein.map { VoxelBlock(position: $0, material: .copperOre) })
        blocks.append(contentsOf: ironVein.map { VoxelBlock(position: $0, material: .ironOre) })
        blocks.append(contentsOf: coalPocket.map { VoxelBlock(position: $0, material: .coal) })

        let factoryLine = [
            VoxelBlock(position: GridPoint(x: 10, y: 6, z: 8), material: .generator),
            VoxelBlock(position: GridPoint(x: 12, y: 6, z: 8), material: .battery),
            VoxelBlock(position: GridPoint(x: 14, y: 6, z: 8), material: .furnace),
            VoxelBlock(position: GridPoint(x: 15, y: 6, z: 8), material: .furnace),
            VoxelBlock(position: GridPoint(x: 16, y: 6, z: 8), material: .steelPlating),
        ]
        blocks.append(contentsOf: factoryLine)

        for x in 9...17 {
            blocks.append(VoxelBlock(position: GridPoint(x: x, y: 6, z: 9), material: .conveyor))
            blocks.append(VoxelBlock(position: GridPoint(x: x, y: 7, z: 7), material: .cable))
        }

        for z in 8...15 {
            blocks.append(VoxelBlock(position: GridPoint(x: 18, y: 6, z: z), material: .conveyor))
        }

        return WorldSnapshot(size: size, blocks: deduplicated(blocks), seed: 420_2026)
    }

    private static func deduplicated(_ blocks: [VoxelBlock]) -> [VoxelBlock] {
        var lookup: [GridPoint: VoxelBlock] = [:]
        for block in blocks {
            lookup[block.position] = block
        }

        return lookup.values.sorted {
            if $0.position.y != $1.position.y {
                return $0.position.y < $1.position.y
            }

            if $0.position.z != $1.position.z {
                return $0.position.z < $1.position.z
            }

            return $0.position.x < $1.position.x
        }
    }
}
