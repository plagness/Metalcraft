# Chunk System

[← Back to README](../README.md)

## Chunk Structure

Each chunk is a 16×16×16 block of voxels (4,096 blocks total):

```swift
class Chunk {
    let position: SIMD3<Int32>           // World-space chunk coordinate
    let blockBuffer: MTLBuffer            // storageModeShared, 8 KB
    let blocks: UnsafeMutablePointer<UInt16>
    var meshAllocation: MeshAllocator.Allocation?
    var meshLODStep: Int                  // 1=full, 2=half, 4=quarter, 8=eighth
}
```

Block data is stored as `UInt16` (2 bytes per block). `storageModeShared` enables zero-copy between CPU and GPU on Apple Silicon's unified memory.

## Chunk Loading

### Ring-Based Streaming

Chunks load outward from camera in concentric rings:

```
Configuration:
  viewDistance      = 64 chunks (1,024 blocks)
  maxLoadPerFrame   = 32 chunks
  maxMeshPerFrame   = 24 chunks
  maxInFlightGen    = 64 GPU tasks
  maxLoadedChunks   = 100,000
  maxRenderChunks   = 4,500
```

The load queue is rebuilt only when the camera enters a new chunk. Ring ordering naturally sorts by distance without explicit sorting.

### Loading Pipeline

```
1. Camera moves → rebuild load queue (if new chunk)
2. Per frame: dequeue up to 32 chunks
3. GPU terrain generate (compute shader)
4. CPU greedy meshing (background thread)
5. Mega-buffer allocation
6. Add to render list
```

## LOD System

Distance-based voxel resolution reduction:

| Distance (chunks) | Distance (blocks) | LOD Step | Resolution | Blocks Sampled |
|---|---|---|---|---|
| 0–10 | 0–160 | 1 | 16×16×16 | 4,096 |
| 10–24 | 160–384 | 2 | 8×8×8 | 512 |
| 24–48 | 384–768 | 4 | 4×4×4 | 64 |
| 48–100 | 768–1,600 | 8 | 2×2×2 | 8 |

At LOD > 1, the greedy mesher samples blocks at `step` intervals, producing a simplified mesh with fewer vertices.

## Greedy Meshing

The greedy mesher merges adjacent same-type block faces into larger quads:

```
For each of 6 face directions (±X, ±Y, ±Z):
  For each slice along that axis:
    Build 16×16 mask of visible block types
    Scan mask for rectangles of same type
    Merge width-first, then height
    Emit one quad per rectangle
```

**LOD 1 (step=1):** Full greedy merge — maximum optimization.
**LOD > 1 (step > 1):** Simplified per-block approach — no complex merging, but still benefits from reduced block count.

### Vertex Format

16-byte packed vertex (vs 48 bytes naive):

```
PackedVoxelVertex (16 bytes)
├── position    Float16×3     6 bytes
├── normalIdx   UInt8         1 byte
├── padding     UInt8         1 byte
├── uv          Float16×2     4 bytes
└── color       RGBA8         4 bytes
```

## Mega-Buffer

All chunk meshes share a single pair of GPU buffers:

- **Vertex buffer:** 128 MB `storageModeShared`
- **Index buffer:** 64 MB `storageModeShared`
- **Allocation:** bump pointer with free list (best-fit)
- **Alignment:** 16 bytes (vertex stride)

Benefits:
- One `setVertexBuffer` call per frame (not 4,500)
- Reduced API overhead
- Better GPU memory locality

## Indirect Command Buffer (ICB)

Instead of 4,500 individual `drawIndexedPrimitives` calls:

```swift
let icbDesc = MTLIndirectCommandBufferDescriptor()
icbDesc.commandTypes = .drawIndexed
icbDesc.inheritBuffers = true
icbDesc.inheritPipelineState = true
```

Each visible chunk encodes one command:
```swift
let cmd = icb.indirectRenderCommandAt(drawIdx)
cmd.drawIndexedPrimitives(
    .triangle,
    indexCount: alloc.indexCount,
    indexType: .uint32,
    indexBuffer: allocator.indexBuffer,
    indexBufferOffset: alloc.indexOffset,
    baseVertex: alloc.vertexOffset / vertexStride,
    baseInstance: instanceIndex
)
```

Execution: one call replaces all draws.
```swift
encoder.executeCommandsInBuffer(icb, range: 0..<drawCount)
```

ICB is re-encoded only when the renderable chunk list changes. Amortized cost: near zero.

## Frustum Culling

```swift
let frustum = Frustum(viewProjection: camera.viewProjectionMatrix)
```

Each chunk's AABB is tested against 6 frustum planes. Optimization: culling is skipped when camera movement is small:
- Moved < 4 blocks
- Rotated < ~3.6°
- Lazy re-cull every 30 frames or on new mesh events

## Block Types

27 block types with individual PBR properties:

| Block | Color (RGBA) | Roughness | Metallic | Transparent | Emissive |
|---|---|---|---|---|---|
| Grass | (0.30, 0.55, 0.25, 1) | 0.85 | 0 | No | No |
| Water | (0.20, 0.40, 0.75, 0.6) | 0.6 | 0 | Yes | No |
| Metal | (0.70, 0.72, 0.75, 1) | 0.3 | 0.9 | No | No |
| Neon Red | (1.00, 0.15, 0.20, 1) | 0.5 | 0 | No | Yes |
| Glass | (0.80, 0.85, 0.90, 0.3) | 0.05 | 0 | Yes | No |
| ... | ... | ... | ... | ... | ... |

Full list: 27 types including stone, dirt, sand, wood, leaves, snow, gravel, ore, lamp, neon (red/blue/green), tall grass, cactus, clay, pine leaves, birch wood, flowers, dead bush, ice, mossy stone.

## Water System

Water uses a separate mesh (WaterMesher) and renders in a forward pass with alpha blending:
- `sourceAlpha / oneMinusSourceAlpha`
- Water mesh is invalidated when adjacent chunks re-mesh
- Separate from opaque geometry to ensure correct transparency ordering

## Key Source Files

| File | Lines | Purpose |
|---|---|---|
| `Voxel/ChunkManager.swift` | ~500 | Chunk lifecycle, LOD, streaming |
| `Voxel/GreedyMesher.swift` | ~480 | Face merging algorithm |
| `Voxel/Chunk.swift` | ~80 | Chunk data structure |
| `Voxel/BlockRegistry.swift` | ~140 | 27 block type definitions |
| `Voxel/WaterMesher.swift` | ~100 | Water mesh generation |
| `Renderer/MeshAllocator.swift` | ~200 | Mega-buffer management |
