# Architecture

[← Back to README](../README.md)

## Overview

Metalcraft uses a **single-pass deferred rendering** pipeline specifically designed for Apple Silicon's tile-based GPU architecture. The entire G-Buffer stays in fast on-chip SRAM and never touches DRAM.

## Render Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                     Render Pipeline                             │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────┐  │
│  │  G-Buffer     │──▶│  Deferred    │──▶│  Water + Particles │  │
│  │  Fill         │   │  PBR Lighting│   │  (Forward Pass)    │  │
│  │  (Tile SRAM)  │   │  (Tile SRAM) │   │                    │  │
│  └──────────────┘   └──────────────┘   └────────────────────┘  │
│         ▲                                         │             │
│         │                                         ▼             │
│  ┌──────────────┐                      ┌────────────────────┐  │
│  │  Chunk        │                      │  Bloom + Tone Map  │  │
│  │  Manager      │                      │  + Composite       │  │
│  │  + ICB        │                      │  → Drawable        │  │
│  └──────────────┘                      └────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Compute Pipeline                            │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────┐  │
│  │  GPU Terrain  │   │  Particle    │   │  Bloom             │  │
│  │  Generation   │   │  Simulation  │   │  Extract/Blur/Up   │  │
│  │  (Perlin)     │   │  (8192)      │   │  (Kawase)          │  │
│  └──────────────┘   └──────────────┘   └────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## How It Works on Apple Silicon

Apple Silicon GPUs use **Tile-Based Deferred Rendering (TBDR)**. Instead of processing the entire screen at once, the GPU divides it into small tiles (~32×32 pixels) and renders each tile entirely in fast on-chip SRAM.

### Traditional GPU (IMR) approach:
1. Write G-Buffer to DRAM → bandwidth cost
2. Read G-Buffer back for lighting → more bandwidth cost
3. At 1080p with 3 render targets: **~58 MB/frame** just for G-Buffer traffic

### Apple Silicon approach (what this engine does):
1. G-Buffer is written to **tile memory** (on-chip SRAM)
2. Lighting reads G-Buffer from **the same tile memory** via programmable blending (`[[color(n)]]`)
3. `storeAction = .dontCare` — G-Buffer is **never written to DRAM**
4. **Result:** ~58 MB/frame bandwidth saved at 1080p

## G-Buffer Layout

All G-Buffer textures use `storeAction = .dontCare` — they exist only in tile memory:

| Attachment | Format | Content | Storage |
|---|---|---|---|
| 0 | RGBA8 | Albedo (RGB) + Metallic (A) | Tile SRAM only |
| 1 | RGBA8 | Normal (RGB) + Roughness (A) | Tile SRAM only |
| 2 | RGBA16F | Emission (RGB) + NDC Depth (A) | Tile SRAM only |
| 3 | RGBA16F | HDR Lit Result | DRAM (output) |

The lighting fragment shader reads attachments 0–2 via Metal's programmable blending:

```metal
struct GBufferInput {
    float4 albedoMetallic  [[color(0)]];   // Read from tile SRAM
    float4 normalRoughness [[color(1)]];   // Read from tile SRAM
    float4 emissionDepth   [[color(2)]];   // Read from tile SRAM
};
```

## Pass Details

### Pass 1: G-Buffer Fill

The vertex shader unpacks `PackedVoxelVertex` (16 bytes) with chunk world origin from `ChunkInfo` buffer. The fragment shader writes albedo, normals, emission, and depth into the G-Buffer.

Bright blocks (brightness > 0.9) are automatically tagged as emissive.

### Pass 2: Deferred Lighting

A fullscreen triangle (3 vertices, no geometry needed) triggers the lighting fragment shader. It reads G-Buffer from tile memory, reconstructs world position from depth, and computes PBR lighting.

See [Shaders → PBR Lighting](shaders.md#pbr-lighting) for the full BRDF details.

### Pass 3: Forward Transparency

Water and particles render on top of the lit result using alpha blending:
- Water: `sourceAlpha / oneMinusSourceAlpha`
- Particles: additive + standard alpha

### Pass 4: Post-Processing

Bloom extraction → Kawase downsample (5-tap) → Kawase upsample (9-tap) → composite with ACES tone mapping.

See [Shaders → Post-Processing](shaders.md#post-processing) for details.

## Triple Buffering

```
Frame N:     CPU writes uniforms[0]
Frame N-1:   GPU renders with uniforms[1]
Frame N-2:   GPU finishes with uniforms[2]
```

3 copies of uniform and light buffers. `DispatchSemaphore(value: 3)` controls frame pacing.

## Key Source Files

| File | Lines | Purpose |
|---|---|---|
| `Renderer/Renderer.swift` | ~600 | Main render pipeline, all passes |
| `Renderer/CameraSystem.swift` | ~120 | FPS camera, projection/view matrices |
| `Renderer/MeshAllocator.swift` | ~200 | Mega-buffer sub-allocator |

## Memory Architecture

Apple Silicon uses **Unified Memory Architecture (UMA)** — CPU and GPU share the same physical memory. All buffers use `storageModeShared` for zero-copy access.

| Resource | Size | Purpose |
|---|---|---|
| Vertex mega-buffer | 128 MB | All chunk meshes |
| Index mega-buffer | 64 MB | All chunk indices |
| Frame uniforms | 384 B × 3 | Per-frame matrices, camera |
| Light buffer | LightData[128] × 3 | Dynamic light array |
| Particle buffer | 48 × 8,192 B | GPU-simulated particles |
| ChunkInfo buffer | ChunkInfo × 4,500 | World origins per instance |
| ICB | Commands × 4,500 | Indirect draw commands |
| G-Buffer textures | 1080p × 3 RT | Tile memory (SRAM) |
| HDR texture | 1080p RGBA16F | Lit result (DRAM) |
| Bloom textures | 4 cascade RGBA16F | Bloom chain |
