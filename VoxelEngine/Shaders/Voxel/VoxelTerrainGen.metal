#include <metal_stdlib>
using namespace metal;

// GPU terrain generation compute shader with smooth biome blending.
// Optimized: tree data precomputed once per column (not per-block).
// Reduced noise octaves for tree surface estimation.

struct TerrainConfig {
    int chunkX;
    int chunkY;
    int chunkZ;
    int seed;
    int seaLevel;
    int baseHeight;
    float heightVariation;
    float terrainScale;
    float detailScale;
    float caveScale;
    float caveThreshold;
    int chunkSize;
};

// Block type IDs (must match BlockType enum in Swift)
constant ushort BLOCK_AIR        = 0;
constant ushort BLOCK_STONE      = 1;
constant ushort BLOCK_DIRT       = 2;
constant ushort BLOCK_GRASS      = 3;
constant ushort BLOCK_SAND       = 4;
constant ushort BLOCK_WATER      = 5;
constant ushort BLOCK_WOOD       = 6;
constant ushort BLOCK_LEAVES     = 7;
constant ushort BLOCK_SNOW       = 8;
constant ushort BLOCK_GRAVEL     = 9;
constant ushort BLOCK_ORE        = 10;
constant ushort BLOCK_TALL_GRASS = 17;
constant ushort BLOCK_DARK_GRASS = 18;
constant ushort BLOCK_CACTUS     = 19;
constant ushort BLOCK_CLAY       = 20;
constant ushort BLOCK_PINE_LEAVES= 21;
constant ushort BLOCK_BIRCH_WOOD = 22;
constant ushort BLOCK_RED_FLOWER = 23;
constant ushort BLOCK_DEAD_BUSH  = 24;
constant ushort BLOCK_ICE        = 25;
constant ushort BLOCK_MOSSY      = 26;

// Biome types
constant int BIOME_OCEAN    = 0;
constant int BIOME_PLAINS   = 1;
constant int BIOME_FOREST   = 2;
constant int BIOME_DESERT   = 3;
constant int BIOME_MOUNTAINS= 4;
constant int BIOME_TUNDRA   = 5;

struct BiomeWeights {
    float w[6];
    int dominant;
    int secondary;
};

// Precomputed tree data — one per nearby grid cell
struct TreeData {
    int treeX, treeZ;
    int treeSurface;
    int trunkHeight;
    int crownRadius;
    int crownHeight;
    int treeBiome;
};

// ============================================================================
// Noise functions
// ============================================================================

static uint pcg_hash(uint input) {
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

static float2 grad2(int2 p, int seed) {
    uint h = pcg_hash(uint(p.x) * 73856093u ^ uint(p.y) * 19349663u ^ uint(seed) * 83492791u);
    float angle = float(h) * (2.0 * M_PI_F / 4294967296.0);
    return float2(cos(angle), sin(angle));
}

static float3 grad3(int3 p, int seed) {
    uint h = pcg_hash(uint(p.x) * 73856093u ^ uint(p.y) * 19349663u ^ uint(p.z) * 83492791u ^ uint(seed) * 2654435761u);
    uint idx = h % 12u;
    constexpr float3 grads[12] = {
        float3(1,1,0), float3(-1,1,0), float3(1,-1,0), float3(-1,-1,0),
        float3(1,0,1), float3(-1,0,1), float3(1,0,-1), float3(-1,0,-1),
        float3(0,1,1), float3(0,-1,1), float3(0,1,-1), float3(0,-1,-1)
    };
    return grads[idx];
}

static float fade(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

static float perlinNoise2D(float2 p, int seed) {
    int2 i = int2(floor(p));
    float2 f = fract(p);
    float2 u = float2(fade(f.x), fade(f.y));
    float n00 = dot(grad2(i + int2(0,0), seed), f - float2(0,0));
    float n10 = dot(grad2(i + int2(1,0), seed), f - float2(1,0));
    float n01 = dot(grad2(i + int2(0,1), seed), f - float2(0,1));
    float n11 = dot(grad2(i + int2(1,1), seed), f - float2(1,1));
    return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}

static float perlinNoise3D(float3 p, int seed) {
    int3 i = int3(floor(p));
    float3 f = fract(p);
    float3 u = float3(fade(f.x), fade(f.y), fade(f.z));
    float n000 = dot(grad3(i + int3(0,0,0), seed), f - float3(0,0,0));
    float n100 = dot(grad3(i + int3(1,0,0), seed), f - float3(1,0,0));
    float n010 = dot(grad3(i + int3(0,1,0), seed), f - float3(0,1,0));
    float n110 = dot(grad3(i + int3(1,1,0), seed), f - float3(1,1,0));
    float n001 = dot(grad3(i + int3(0,0,1), seed), f - float3(0,0,1));
    float n101 = dot(grad3(i + int3(1,0,1), seed), f - float3(1,0,1));
    float n011 = dot(grad3(i + int3(0,1,1), seed), f - float3(0,1,1));
    float n111 = dot(grad3(i + int3(1,1,1), seed), f - float3(1,1,1));
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

static float fbm2D(float2 p, int seed, int octaves, float persistence) {
    float sum = 0.0, amp = 1.0, freq = 1.0, maxAmp = 0.0;
    for (int i = 0; i < octaves; i++) {
        sum += perlinNoise2D(p * freq, seed + i * 31) * amp;
        maxAmp += amp;
        amp *= persistence;
        freq *= 2.0;
    }
    return sum / maxAmp;
}

static float fbm3D(float3 p, int seed, int octaves, float persistence) {
    float sum = 0.0, amp = 1.0, freq = 1.0, maxAmp = 0.0;
    for (int i = 0; i < octaves; i++) {
        sum += perlinNoise3D(p * freq, seed + i * 31) * amp;
        maxAmp += amp;
        amp *= persistence;
        freq *= 2.0;
    }
    return sum / maxAmp;
}

// ============================================================================
// Biome determination
// ============================================================================

static float hashPos(int x, int z, int seed) {
    uint h = pcg_hash(uint(x) * 73856093u ^ uint(z) * 19349663u ^ uint(seed) * 2654435761u);
    return float(h) / 4294967296.0;
}

// Fast biome — nearest center (for tree placement, uses 2 octaves)
static int getBiomeFast(float2 pos, int seed) {
    float temperature = fbm2D(pos * 0.0015, seed + 100, 2, 0.5);
    float humidity    = fbm2D(pos * 0.0018, seed + 200, 2, 0.5);
    float2 point = float2(temperature, humidity);

    constexpr float2 centers[6] = {
        float2(0.0, -0.45), float2(0.1, -0.05), float2(0.15, 0.35),
        float2(0.4, -0.25), float2(-0.15, 0.15), float2(-0.4, 0.1),
    };

    int closest = 1;
    float minDist = 999.0;
    for (int i = 0; i < 6; i++) {
        float d = length(point - centers[i]);
        if (d < minDist) { minDist = d; closest = i; }
    }
    return closest;
}

// Full biome weights for smooth height blending
static BiomeWeights getBiomeWeights(float2 pos, int seed) {
    float temperature = fbm2D(pos * 0.0015, seed + 100, 3, 0.5);
    float humidity    = fbm2D(pos * 0.0018, seed + 200, 3, 0.5);
    float2 point = float2(temperature, humidity);

    constexpr float2 centers[6] = {
        float2(0.0, -0.45), float2(0.1, -0.05), float2(0.15, 0.35),
        float2(0.4, -0.25), float2(-0.15, 0.15), float2(-0.4, 0.1),
    };

    BiomeWeights bw;
    float total = 0.0;
    for (int i = 0; i < 6; i++) {
        float d = length(point - centers[i]);
        bw.w[i] = exp(-d * 7.0);
        total += bw.w[i];
    }

    float maxW = -1.0, secondW = -1.0;
    bw.dominant = 1;
    bw.secondary = 0;
    for (int i = 0; i < 6; i++) {
        bw.w[i] /= total;
        if (bw.w[i] > maxW) {
            secondW = maxW; bw.secondary = bw.dominant;
            maxW = bw.w[i]; bw.dominant = i;
        } else if (bw.w[i] > secondW) {
            secondW = bw.w[i]; bw.secondary = i;
        }
    }
    return bw;
}

// ============================================================================
// Terrain height — blended across biomes
// ============================================================================

static float biomeHeightFor(int biome, float continental, float hills, float detail, float ridged,
                            constant TerrainConfig &cfg) {
    switch (biome) {
        case BIOME_OCEAN:
            return float(cfg.seaLevel) - 12.0 + continental * 8.0 + detail * 2.0;
        case BIOME_PLAINS:
            return float(cfg.baseHeight) + continental * 8.0 + hills * 5.0 + detail * 3.0;
        case BIOME_FOREST:
            return float(cfg.baseHeight) + 5.0 + continental * 10.0 + hills * 8.0 + detail * 3.0;
        case BIOME_DESERT:
            return float(cfg.baseHeight) - 3.0 + continental * 4.0 + hills * 2.0 + detail * 1.5;
        case BIOME_MOUNTAINS:
            return float(cfg.baseHeight) + 25.0
                   + continental * cfg.heightVariation * 2.0
                   + ridged * cfg.heightVariation * 1.5
                   + hills * 10.0 + detail * 4.0;
        case BIOME_TUNDRA:
            return float(cfg.baseHeight) + 8.0 + continental * 12.0 + hills * 6.0 + detail * 2.0;
        default:
            return float(cfg.baseHeight) + continental * cfg.heightVariation;
    }
}

static int terrainHeight(float wx, float wz, constant TerrainConfig &cfg, BiomeWeights bw) {
    float2 pos = float2(wx, wz);
    float continental = fbm2D(pos * cfg.terrainScale * 0.5, cfg.seed, 4, 0.45);
    float hills       = fbm2D(pos * cfg.terrainScale, cfg.seed + 1000, 4, 0.5);  // was 5 octaves → 4
    float detail      = fbm2D(pos * cfg.detailScale, cfg.seed + 2000, 3, 0.6);
    float ridged      = abs(fbm2D(pos * cfg.terrainScale * 0.8, cfg.seed + 3000, 3, 0.5));  // was 4 → 3

    float h = 0.0;
    for (int i = 0; i < 6; i++) {
        if (bw.w[i] > 0.01) {
            h += bw.w[i] * biomeHeightFor(i, continental, hills, detail, ridged, cfg);
        }
    }
    return max(1, int(h));
}

// ============================================================================
// Tree precomputation — find all trees near a column ONCE
// ============================================================================

// Find up to 9 trees near (wx, wz). Returns count.
static int findNearbyTrees(int wx, int wz, int biome, float biomeWeight, int seed,
                           thread TreeData *trees) {
    if (biome == BIOME_OCEAN || biome == BIOME_DESERT) return 0;
    if (biomeWeight < 0.35) return 0;

    int spacing = (biome == BIOME_FOREST) ? 5 : 8;
    int count = 0;

    for (int gx = -1; gx <= 1; gx++) {
        for (int gz = -1; gz <= 1; gz++) {
            int cellX = (int(floor(float(wx) / float(spacing))) + gx) * spacing;
            int cellZ = (int(floor(float(wz) / float(spacing))) + gz) * spacing;

            float treeChance = hashPos(cellX, cellZ, seed + 7777);
            float threshold = (biome == BIOME_FOREST) ? 0.45 : 0.75;
            if (biome == BIOME_TUNDRA) threshold = 0.65;
            if (treeChance > threshold) continue;

            int treeX = cellX + int(hashPos(cellX, cellZ, seed + 8888) * float(spacing - 1));
            int treeZ = cellZ + int(hashPos(cellX, cellZ, seed + 9999) * float(spacing - 1));

            // Reduced octaves for tree surface estimation (3+3+2 vs 4+5+3)
            float2 treePos = float2(float(treeX), float(treeZ));
            float tc = fbm2D(treePos * 0.004, seed, 3, 0.45);
            float th = fbm2D(treePos * 0.008, seed + 1000, 3, 0.5);
            float td = fbm2D(treePos * 0.04, seed + 2000, 2, 0.6);
            int treeBiome = getBiomeFast(treePos, seed);  // 2-octave biome

            float baseH;
            if (treeBiome == BIOME_FOREST) baseH = 45.0 + tc * 10.0 + th * 8.0 + td * 3.0;
            else if (treeBiome == BIOME_TUNDRA) baseH = 48.0 + tc * 12.0 + th * 6.0 + td * 2.0;
            else baseH = 40.0 + tc * 8.0 + th * 5.0 + td * 3.0;
            int treeSurface = max(1, int(baseH));

            if (treeSurface <= 32 || treeSurface > 75) continue;

            TreeData td2;
            td2.treeX = treeX;
            td2.treeZ = treeZ;
            td2.treeSurface = treeSurface;
            float sizeHash = hashPos(treeX, treeZ, seed + 5555);
            td2.trunkHeight = 4 + int(sizeHash * 4.0);
            td2.crownRadius = (treeBiome == BIOME_TUNDRA) ? 1 : 2;
            td2.crownHeight = (treeBiome == BIOME_TUNDRA) ? td2.trunkHeight - 1 : 3;
            td2.treeBiome = treeBiome;
            trees[count++] = td2;
        }
    }
    return count;
}

// Check if (wx, wy, wz) is part of any precomputed tree. Returns block or BLOCK_AIR.
static ushort treeBlockAt(int wx, int wy, int wz, thread TreeData *trees, int treeCount) {
    for (int t = 0; t < treeCount; t++) {
        TreeData td = trees[t];
        int dx = wx - td.treeX;
        int dz = wz - td.treeZ;
        int dy = wy - td.treeSurface;

        // Trunk
        if (dx == 0 && dz == 0 && dy >= 1 && dy <= td.trunkHeight) {
            return (td.treeBiome == BIOME_TUNDRA) ? BLOCK_BIRCH_WOOD : BLOCK_WOOD;
        }

        // Crown
        int crownBase = td.treeSurface + td.trunkHeight - td.crownHeight;
        if (wy >= crownBase && wy <= td.treeSurface + td.trunkHeight + 1) {
            int dist2 = dx * dx + dz * dz;
            if (td.treeBiome == BIOME_TUNDRA) {
                int layerFromTop = (td.treeSurface + td.trunkHeight + 1) - wy;
                int layerRadius = min(layerFromTop, 2);
                if (dist2 <= layerRadius * layerRadius) return BLOCK_PINE_LEAVES;
            } else {
                if (dist2 <= td.crownRadius * td.crownRadius) return BLOCK_LEAVES;
            }
        }
    }
    return BLOCK_AIR;
}

// ============================================================================
// Surface/subsurface helpers
// ============================================================================

static ushort surfaceBlockForBiome(int biome, int surfaceHeight, int seaLevel) {
    switch (biome) {
        case BIOME_OCEAN:
            return (surfaceHeight <= seaLevel + 2) ? BLOCK_SAND : BLOCK_GRASS;
        case BIOME_PLAINS:
            return (surfaceHeight <= seaLevel + 2) ? BLOCK_SAND : BLOCK_GRASS;
        case BIOME_FOREST:
            return BLOCK_DARK_GRASS;
        case BIOME_DESERT:
            return BLOCK_SAND;
        case BIOME_MOUNTAINS:
            if (surfaceHeight > 85) return BLOCK_SNOW;
            if (surfaceHeight > 70) return BLOCK_STONE;
            if (surfaceHeight > 55) return BLOCK_GRAVEL;
            return BLOCK_GRASS;
        case BIOME_TUNDRA:
            return (surfaceHeight > 65) ? BLOCK_SNOW : BLOCK_GRASS;
        default:
            return BLOCK_GRASS;
    }
}

static ushort subsurfaceBlockForBiome(int biome, int surfaceHeight, int depth, int seaLevel) {
    switch (biome) {
        case BIOME_DESERT: return BLOCK_SAND;
        case BIOME_OCEAN:  return (surfaceHeight <= seaLevel) ? BLOCK_CLAY : BLOCK_DIRT;
        case BIOME_TUNDRA: return (depth < 2 && surfaceHeight > 60) ? BLOCK_GRAVEL : BLOCK_DIRT;
        default: return BLOCK_DIRT;
    }
}

// ============================================================================
// Block determination
// ============================================================================

static ushort blockAt(int wx, int wy, int wz, int surfaceHeight, BiomeWeights bw,
                      constant TerrainConfig &cfg,
                      thread TreeData *trees, int treeCount) {
    int biome = bw.dominant;

    // Above surface
    if (wy > surfaceHeight) {
        // Tree check — only within possible tree height (max surface 75 + trunk 8 + crown 2 = 85)
        if (wy <= 85 && treeCount > 0) {
            ushort treeBlock = treeBlockAt(wx, wy, wz, trees, treeCount);
            if (treeBlock != BLOCK_AIR) return treeBlock;
        }

        // Decorations one block above surface
        if (wy == surfaceHeight + 1 && surfaceHeight > cfg.seaLevel) {
            float decor = hashPos(wx, wz, cfg.seed + 4444);
            if (biome == BIOME_PLAINS) {
                if (decor < 0.15) return BLOCK_TALL_GRASS;
                if (decor < 0.17) return BLOCK_RED_FLOWER;
            }
            if (biome == BIOME_FOREST) {
                if (decor < 0.20) return BLOCK_TALL_GRASS;
                if (decor < 0.22) return BLOCK_RED_FLOWER;
            }
            if (biome == BIOME_DESERT) {
                if (decor < 0.02) return BLOCK_CACTUS;
                if (decor < 0.05) return BLOCK_DEAD_BUSH;
            }
        }
        // Cactus 2-3 blocks tall
        if (biome == BIOME_DESERT && (wy == surfaceHeight + 2 || wy == surfaceHeight + 3)) {
            float decor = hashPos(wx, wz, cfg.seed + 4444);
            if (decor < 0.02) {
                float heightHash = hashPos(wx, wz, cfg.seed + 6666);
                if (wy - surfaceHeight <= 1 + int(heightHash * 3.0)) return BLOCK_CACTUS;
            }
        }

        if (wy <= cfg.seaLevel) return BLOCK_WATER;
        return BLOCK_AIR;
    }

    // Cave carving
    if (wy > 2 && wy < surfaceHeight - 4) {
        float3 cavePos = float3(float(wx), float(wy), float(wz));
        float cave = fbm3D(cavePos * cfg.caveScale, cfg.seed + 12345, 3, 0.5);
        if (cave > cfg.caveThreshold) return BLOCK_AIR;
        if (wy < 20) {
            float bigCave = fbm3D(cavePos * cfg.caveScale * 0.5, cfg.seed + 54321, 2, 0.6);
            if (bigCave > cfg.caveThreshold - 0.05) return BLOCK_AIR;
        }
    }

    // Ravines
    if (wy > 5 && wy < surfaceHeight - 2) {
        float ravine = perlinNoise2D(float2(float(wx) * 0.02, float(wz) * 0.02), cfg.seed + 77777);
        float ravineWidth = perlinNoise2D(float2(float(wx) * 0.005, float(wz) * 0.005), cfg.seed + 88888);
        if (abs(ravine) < 0.015 + ravineWidth * 0.01 && wy > surfaceHeight - 25) {
            return BLOCK_AIR;
        }
    }

    int depth = surfaceHeight - wy;

    // Surface — dither between biomes in transition zones
    if (depth == 0) {
        int effectiveBiome = biome;
        if (bw.w[biome] < 0.65) {
            float r = hashPos(wx, wz, cfg.seed + 3333);
            float p = bw.w[biome] / (bw.w[biome] + bw.w[bw.secondary]);
            if (r > p) effectiveBiome = bw.secondary;
        }
        return surfaceBlockForBiome(effectiveBiome, surfaceHeight, cfg.seaLevel);
    }

    // Subsurface — also dither
    if (depth < 4) {
        int effectiveBiome = biome;
        if (bw.w[biome] < 0.65) {
            float r = hashPos(wx + depth * 97, wz, cfg.seed + 3334);
            float p = bw.w[biome] / (bw.w[biome] + bw.w[bw.secondary]);
            if (r > p) effectiveBiome = bw.secondary;
        }
        return subsurfaceBlockForBiome(effectiveBiome, surfaceHeight, depth, cfg.seaLevel);
    }

    if (depth < 8) {
        float mossy = perlinNoise3D(float3(float(wx), float(wy), float(wz)) * 0.08, cfg.seed + 6000);
        if (mossy > 0.6) return BLOCK_MOSSY;
        return BLOCK_STONE;
    }

    float oreNoise = perlinNoise3D(float3(float(wx), float(wy), float(wz)) * 0.1, cfg.seed + 5000);
    if (oreNoise > 0.7) return BLOCK_ORE;
    return BLOCK_STONE;
}

// ============================================================================
// Compute Kernel
// ============================================================================

kernel void terrain_generate(
    device ushort *blocks [[buffer(0)]],
    constant TerrainConfig &config [[buffer(1)]],
    uint2 tid [[thread_position_in_grid]]
) {
    int lx = int(tid.x);
    int lz = int(tid.y);
    int cs = config.chunkSize;
    if (lx >= cs || lz >= cs) return;

    int cx = config.chunkX * cs;
    int cy = config.chunkY * cs;
    int cz = config.chunkZ * cs;
    int wx = cx + lx;
    int wz = cz + lz;

    // Compute biome weights once per column
    float2 pos = float2(float(wx), float(wz));
    BiomeWeights bw = getBiomeWeights(pos, config.seed);

    // Blended terrain height
    int height = terrainHeight(float(wx), float(wz), config, bw);

    // Precompute tree data once per column (not per block!)
    TreeData trees[9];
    int treeCount = findNearbyTrees(wx, wz, bw.dominant, bw.w[bw.dominant], config.seed, trees);

    for (int ly = 0; ly < cs; ly++) {
        int wy = cy + ly;
        ushort block = blockAt(wx, wy, wz, height, bw, config, trees, treeCount);
        int idx = lx + ly * cs + lz * cs * cs;
        blocks[idx] = block;
    }
}
