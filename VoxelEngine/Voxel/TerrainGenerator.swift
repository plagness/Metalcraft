import simd

/// Procedural terrain generator using layered simplex noise.
class TerrainGenerator {

    let noise: SimplexNoise
    let caveNoise: SimplexNoise

    let seaLevel: Int = 32
    let baseHeight: Int = 40
    let heightVariation: Float = 30.0
    let terrainScale: Float = 0.008   // Lower = wider features
    let detailScale: Float = 0.04     // Higher frequency detail
    let caveScale: Float = 0.05
    let caveThreshold: Float = 0.72

    init(seed: Int = 42) {
        self.noise = SimplexNoise(seed: seed)
        self.caveNoise = SimplexNoise(seed: seed &+ 12345)
    }

    /// Generate all blocks for a chunk at the given chunk coordinate.
    func generate(chunk: Chunk) {
        let cx = Int(chunk.position.x) * CHUNK_SIZE
        let cy = Int(chunk.position.y) * CHUNK_SIZE
        let cz = Int(chunk.position.z) * CHUNK_SIZE

        for lz in 0..<CHUNK_SIZE {
            for lx in 0..<CHUNK_SIZE {
                let wx = cx + lx
                let wz = cz + lz

                // Compute terrain height at this column
                let height = terrainHeight(worldX: wx, worldZ: wz)

                for ly in 0..<CHUNK_SIZE {
                    let wy = cy + ly
                    let blockType = blockAt(worldX: wx, worldY: wy, worldZ: wz, surfaceHeight: height)
                    chunk.blocks[Chunk.index(x: lx, y: ly, z: lz)] = blockType.rawValue
                }
            }
        }

        chunk.updateIsEmpty()
        chunk.isDirty = true
    }

    // MARK: - Terrain Shape

    /// Compute the surface height at a world (x, z) column.
    func terrainHeight(worldX: Int, worldZ: Int) -> Int {
        let fx = Float(worldX)
        let fz = Float(worldZ)

        // Base continental shape (low frequency)
        let continental = noise.fbm2D(
            x: fx * terrainScale * 0.5,
            y: fz * terrainScale * 0.5,
            octaves: 4,
            persistence: 0.45
        )

        // Medium frequency hills
        let hills = noise.fbm2D(
            x: fx * terrainScale,
            y: fz * terrainScale,
            octaves: 5,
            persistence: 0.5
        )

        // High frequency detail
        let detail = noise.fbm2D(
            x: fx * detailScale,
            y: fz * detailScale,
            octaves: 3,
            persistence: 0.6
        )

        // Combine layers
        let h = Float(baseHeight)
            + continental * heightVariation * 1.5
            + hills * heightVariation * 0.6
            + detail * 4.0

        return max(1, Int(h))
    }

    /// Determine block type at a specific world coordinate.
    func blockAt(worldX: Int, worldY: Int, worldZ: Int, surfaceHeight: Int) -> BlockType {
        if worldY > surfaceHeight {
            // Above surface — water or air
            if worldY <= seaLevel {
                return .water
            }
            return .air
        }

        // Cave carving using 3D noise (only deep underground, not near surface)
        if worldY > 2 && worldY < surfaceHeight - 8 {
            let cave = caveNoise.fbm3D(
                x: Float(worldX) * caveScale,
                y: Float(worldY) * caveScale * 1.5, // Stretch vertically
                z: Float(worldZ) * caveScale,
                octaves: 3,
                persistence: 0.5
            )
            if cave > caveThreshold {
                return .air
            }
        }

        // Surface and below
        let depth = surfaceHeight - worldY

        if depth == 0 {
            // Surface block
            if surfaceHeight <= seaLevel + 2 {
                return .sand
            } else if surfaceHeight > 80 {
                return .snow
            } else {
                return .grass
            }
        } else if depth < 4 {
            // Subsurface
            if surfaceHeight <= seaLevel + 2 {
                return .sand
            }
            return .dirt
        } else {
            // Deep underground
            // Ore veins
            let oreNoise = noise.noise3D(
                x: Float(worldX) * 0.1,
                y: Float(worldY) * 0.1,
                z: Float(worldZ) * 0.1
            )
            if oreNoise > 0.7 {
                return .ore
            }
            return .stone
        }
    }
}
