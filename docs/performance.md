# Performance

[← Back to README](../README.md)

## Key Metrics

| Metric | Value |
|---|---|
| View distance | 64 chunks (1,024 blocks) |
| Max loaded chunks | 100,000 |
| Max rendered chunks/frame | 4,500 |
| Chunk load throttle | 32/frame |
| Mesh generation throttle | 24/frame |
| GPU terrain tasks in-flight | 64 |
| Vertex format size | 16 bytes (packed) |
| Vertex mega-buffer | 128 MB |
| Index mega-buffer | 64 MB |
| G-Buffer bandwidth saved | ~58 MB/frame (1080p) |
| GPU-simulated particles | 8,192 |
| Frames in-flight | 3 (triple buffering) |
| Block types | 27 (with PBR properties) |
| Biomes | 6 (smooth blending) |
| Dynamic point lights | 16 (animated PBR) |
| Bloom passes | 4 mip levels (Kawase) |

## FPS Tracking

FPS is measured every 0.5 seconds with exponential smoothing (90/10 blend):

```swift
smoothFPS = smoothFPS * 0.9 + fps * 0.1
```

Stats are written to `/tmp/voxel_stats.txt` every 30 frames:
```
FPS: 58.2 | Chunks: 2847/4500 | Tris: 1200K | Verts: 890K | GPUwait: 2.1ms | Pos: 123.5,45.0,678.9
```

## GPU Wait Time

The renderer tracks how long the CPU blocks waiting for the GPU:

```swift
frameSemaphore.wait()  // Block if 3 frames already in-flight
let waitMs = (CACurrentMediaTime() - waitStart) * 1000.0
```

Low GPU wait (< 2ms) = GPU-bound. High GPU wait (> 5ms) = CPU has headroom.

## Bandwidth Analysis

### Without tile memory optimization (traditional IMR):
- G-Buffer write: 3 textures × 1080p × format size = **~29 MB**
- G-Buffer read: same = **~29 MB**
- **Total: ~58 MB/frame** just for G-Buffer

### With tile memory (this engine):
- G-Buffer: **0 MB** DRAM bandwidth (stays in SRAM)
- Only HDR output written to DRAM: ~8 MB/frame

### Savings: ~50 MB/frame at 1080p, scales with resolution.

## Chunk Loading Strategy

Chunks load in a ring pattern from camera center outward:

```
Ring 0 (closest):  immediate load, LOD 1 (full res)
Ring 1:            queued, LOD 1
Ring 2-10:         LOD 1
Ring 10-24:        LOD 2 (half res)
Ring 24-48:        LOD 4 (quarter res)
Ring 48-64:        LOD 8 (eighth res)
```

Load queue is rebuilt only when camera enters a new chunk — not every frame.

## Frustum Culling Optimization

Culling is not recomputed every frame. It skips if:
- Camera moved less than 4 blocks
- Camera rotated less than ~3.6° (`forwardDot < 0.998`)

Lazy re-cull every 30 frames or when new meshes appear.

## Draw Call Reduction

| Approach | Draw calls/frame |
|---|---|
| Naive (one per chunk) | 4,500 |
| Mega-buffer (one bind) | 4,500 (but faster) |
| **ICB (indirect commands)** | **1** |

The Indirect Command Buffer encodes all 4,500 `drawIndexedPrimitives` commands and executes them with a single `executeCommandsInBuffer`. Amortized cost: ~0.07ms (re-encoded only when chunk list changes).

## Greedy Meshing Impact

For a typical chunk with mixed terrain:

| Method | Vertices | Triangles |
|---|---|---|
| Naive (6 faces × 4 verts) | ~24,000 | ~12,000 |
| Greedy meshing | ~3,000–6,000 | ~1,500–3,000 |
| **Reduction** | **~75–87%** | **~75–87%** |

Packed vertex format saves an additional 67% memory (16 bytes vs 48 bytes naive).
