> 🇬🇧 **English** | [🇷🇺 Русский](README.ru.md)

<div align="center">

# ⛏ Metalcraft

**Voxel engine built from scratch in Swift + Metal for Apple Silicon**

*An experiment in pushing Apple's TBDR GPU architecture to its limits — zero dependencies, pure performance*

<br>

![Screenshot](Screenshots/2026-03-10.png)

<br>

[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![Metal](https://img.shields.io/badge/Metal-API-8A8A8A?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/metal/)
[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=for-the-badge&logo=macos&logoColor=white)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1+-FF3B30?style=for-the-badge&logo=apple&logoColor=white)](https://support.apple.com/en-us/116943)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=for-the-badge)](LICENSE)
[![LOC](https://img.shields.io/badge/Lines_of_Code-~4600-8B5CF6?style=for-the-badge)]()
[![Dependencies](https://img.shields.io/badge/Dependencies-0-22C55E?style=for-the-badge)]()

</div>

---

## 🔍 About

This is a **from-scratch voxel engine** that I built as an experiment to explore how far you can push a single Apple Silicon chip using only native frameworks.

**The question:** Can you build a Minecraft-scale voxel renderer with deferred PBR lighting, GPU terrain generation, and 100K loaded chunks — using nothing but Swift and Metal?

**The answer:** Yes. Here's how.

**Key facts:**
- 🏗️ ~4,600 lines of code (14 Swift files + 7 Metal shaders + 1 bridging header)
- 📦 Zero external dependencies — pure Apple frameworks
- ⚡ Single-pass deferred rendering exploiting TBDR tile memory
- 🌍 64-chunk view distance with 4-level LOD
- 🎮 Real-time GPU terrain generation with 6 biomes

---

## 🏛️ Architecture

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

---

## ⚙️ Key Technologies

### 🔲 Single-Pass Deferred Rendering (TBDR)

The core innovation. On Apple Silicon, the GPU is a **Tile-Based Deferred Renderer** — it processes the screen in small tiles using fast on-chip SRAM.

This engine exploits that by keeping the entire G-Buffer in **tile memory** and never writing it to DRAM:

| G-Buffer Layer | Format | Content | Storage |
|---|---|---|---|
| Attachment 0 | RGBA8 | Albedo (RGB) + Metallic (A) | Tile SRAM only |
| Attachment 1 | RGBA8 | Normal (RGB) + Roughness (A) | Tile SRAM only |
| Attachment 2 | RGBA16F | Emission (RGB) + Depth (A) | Tile SRAM only |
| Attachment 3 | RGBA16F | HDR Lit Result | DRAM (output) |

The lighting pass reads the G-Buffer via Metal's **programmable blending** (`[[color(n)]]`) — directly from tile SRAM, zero DRAM bandwidth.

> **Result:** ~58 MB/frame bandwidth saved at 1080p compared to traditional IMR deferred rendering.

### 🎨 PBR Lighting

Cook-Torrance BRDF with:
- **D** — GGX normal distribution
- **G** — Smith geometry function
- **F** — Schlick Fresnel approximation

Light sources:
- ☀️ Directional sun (warm, high-intensity)
- 💡 16 animated point lights (HSV rainbow, orbiting)
- 🌐 Hemispherical ambient (sky-ground gradient)
- 🌫️ Atmospheric distance + height fog

### 📦 Chunk System

- **Chunk size:** 16×16×16 voxels (4,096 blocks each)
- **View distance:** 64 chunks radius (1,024 blocks)
- **Max loaded:** 100,000 chunks
- **Max rendered/frame:** 4,500 chunks
- **Loading throttle:** 32 chunks/frame
- **Meshing throttle:** 24 chunks/frame
- **Ring-based streaming** — natural distance ordering, center-outward

### 🧊 LOD System

Distance-based voxel skipping for far chunks:

| Distance | LOD Step | Effective Resolution |
|---|---|---|
| 0–160 blocks | 1 | Full 16×16×16 |
| 160–384 blocks | 2 | 8×8×8 |
| 384–768 blocks | 4 | 4×4×4 |
| 768–1600 blocks | 8 | 2×2×2 |

### 🔗 Greedy Meshing

Merges adjacent same-type block faces into larger quads. Dramatically reduces vertex count.

**Packed vertex format** — only 16 bytes per vertex:
```
PackedVoxelVertex (16 bytes)
├── position    Float16×3     6 bytes
├── normalIdx   UInt8         1 byte  (0–5 for ±X/±Y/±Z)
├── padding     UInt8         1 byte
├── uv          Float16×2     4 bytes
└── color       RGBA8         4 bytes
```

### 📐 Mega-Buffer + Indirect Command Buffer

All chunk meshes live in **one shared buffer**:
- **Vertex buffer:** 128 MB (single `MTLBuffer`)
- **Index buffer:** 64 MB (single `MTLBuffer`)
- **One** `setVertexBuffer` call per frame instead of 4,500

**Indirect Command Buffer (ICB):** 4,500 individual `drawIndexedPrimitives` calls encoded into a single `executeCommandsInBuffer`. Re-encoded only when the visible chunk list changes.

### 🌍 GPU Compute Terrain Generation

Terrain generated entirely on GPU via compute shaders:
- **Perlin noise** (PCG hash-based, deterministic)
- **6 biomes** with smooth weighted blending: Ocean, Plains, Forest, Desert, Mountains, Tundra
- **Cave carving** (3D noise threshold)
- **Tree placement** with biome-specific properties
- **Performance:** 10–50× faster than CPU equivalent
- **Memory:** `storageModeShared` — zero-copy on Apple Silicon's unified memory

### ✨ GPU Particle System

- **8,192 particles** simulated via compute shader
- Physics: gravity, wind, lifetime
- Rendered as camera-facing billboards
- Additive + alpha blending

### 🌸 Post-Processing

- **Bloom:** Kawase blur (5-tap down, 9-tap up) across 4 mip levels
- **Tone mapping:** ACES filmic
- **Vignette** + composite to drawable

---

## 📊 Performance Metrics

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

---

## 🧠 How TBDR Works (and Why This Engine Exists)

Traditional GPUs (NVIDIA, AMD) use **Immediate Mode Rendering (IMR)** — they process triangles one by one and write results directly to DRAM.

Apple Silicon uses **Tile-Based Deferred Rendering (TBDR)**:

1. The GPU divides the screen into small tiles (~32×32 pixels)
2. Each tile is rendered entirely in **fast on-chip SRAM** (tile memory)
3. Only the final pixel result is written to DRAM

**Why this matters for deferred rendering:**

On IMR GPUs, deferred rendering requires:
- **Write** G-Buffer to DRAM (bandwidth cost)
- **Read** G-Buffer back for lighting (more bandwidth cost)
- At 1080p with 3 render targets: ~58 MB/frame just for G-Buffer traffic

On Apple Silicon TBDR:
- G-Buffer is written to **tile memory** (fast SRAM)
- Lighting reads G-Buffer from **the same tile memory**
- `storeAction = .dontCare` — G-Buffer is **never written to DRAM**
- Metal's `[[color(n)]]` attribute enables reading within the same render pass

**Result:** The entire G-Buffer bandwidth cost is eliminated. This engine was built specifically to demonstrate this advantage.

---

## 🤖 Neural Engine

> **Status:** Architecture prepared, integration in progress

The project includes a dedicated `NeuralEngine/` module designed for future Apple Neural Engine (ANE) integration via CoreML.

**Planned capabilities:**
- 🔬 **ML-based upscaling** — render at lower resolution, upscale via ANE (similar to DLSS/FSR but on Apple's neural hardware)
- 🎨 **Denoising** — real-time denoise for ray-traced passes
- 🧭 **LOD prediction** — ML-driven LOD selection based on camera trajectory
- 🌍 **Terrain enhancement** — neural-assisted terrain detail generation

**Why ANE for a voxel engine?**
Apple Silicon's Neural Engine (up to 38 TOPS on M4) runs independently from the GPU. This means ML inference for upscaling/denoising can happen **in parallel** with GPU rendering — effectively free compute for visual quality improvements.

The `NeuralEngine/Models/` directory is prepared for CoreML model files (`.mlmodelc`).

---

## 🧰 Frameworks

| Framework | Purpose |
|---|---|
| `Metal` | GPU rendering & compute shaders |
| `MetalKit` | View management, drawable lifecycle |
| `simd` | CPU-side vector/matrix math |
| `CoreGraphics` | Debug overlay text rasterization |
| `CoreText` | Font layout for debug HUD |
| `Cocoa` | Application lifecycle, window management |
| `QuartzCore` | High-precision timing (`CACurrentMediaTime`) |
| `Foundation` | Base types, dispatch queues |

> **Zero external dependencies.** No SPM packages. No CocoaPods. No Carthage. Just Apple frameworks.

---

## 📁 Project Structure

```
Metalcraft/
├── project.yml                          # XcodeGen project definition
├── Screenshots/                         # Build screenshots
├── VoxelEngine/
│   ├── App/                             # Entry point, window, view controller
│   │   ├── main.swift
│   │   ├── AppDelegate.swift
│   │   ├── GameViewController.swift
│   │   └── MetalView.swift
│   ├── Core/                            # Time tracking, delta time
│   ├── Input/                           # Keyboard + mouse FPS controls
│   ├── Math/                            # Noise generation, frustum culling
│   ├── Renderer/                        # Metal renderer, camera, mega-buffer
│   │   ├── Renderer.swift               # Main render pipeline (~600 lines)
│   │   ├── CameraSystem.swift           # FPS camera, projection matrices
│   │   └── MeshAllocator.swift          # Mega-buffer sub-allocator
│   ├── Compute/                         # GPU terrain generation
│   ├── Voxel/                           # Chunk system, block types, meshing
│   │   ├── ChunkManager.swift           # Streaming, LOD, loading (~500 lines)
│   │   ├── GreedyMesher.swift           # Face merging optimization
│   │   ├── BlockRegistry.swift          # 27 block types with PBR props
│   │   └── WaterMesher.swift            # Transparent water mesh
│   ├── Debug/                           # FPS overlay (CoreText → texture)
│   ├── Shaders/                         # Metal Shading Language
│   │   ├── Common/ShaderTypes.h         # Swift-Metal bridging types
│   │   ├── Deferred/                    # G-Buffer fill + PBR lighting
│   │   ├── Transparency/               # Water forward pass
│   │   ├── Particles/                   # GPU compute + billboard render
│   │   ├── PostProcess/                 # Bloom (Kawase), tone mapping
│   │   ├── Voxel/                       # GPU terrain compute shader
│   │   └── Utility/                     # Fullscreen triangle
│   ├── NeuralEngine/                    # [Planned] CoreML / ANE
│   └── ECS/                             # [Planned] Entity-Component-System
└── VoxelEngine.xcodeproj/               # Xcode project (ready to build)
```

---

## 📋 Requirements

| Requirement | Minimum |
|---|---|
| **Operating System** | macOS 14.0 (Sonoma) |
| **Hardware** | Apple Silicon (M1 / M2 / M3 / M4) |
| **GPU Family** | Metal GPU Family Apple 7+ |
| **Xcode** | 15.0+ |
| **Swift** | 5.9 |

> ⚠️ **Intel Macs are not supported.** The engine requires Apple Silicon's unified memory architecture and TBDR tile memory features.

---

## 🚀 Building & Running

### Option A — Direct (recommended)

```bash
git clone https://github.com/plagness/Metalcraft.git
cd Metalcraft
open VoxelEngine.xcodeproj
# Press Cmd+R to build and run
```

### Option B — Regenerate with XcodeGen

```bash
brew install xcodegen
git clone https://github.com/plagness/Metalcraft.git
cd Metalcraft
xcodegen generate
open VoxelEngine.xcodeproj
```

### 🎮 Controls

| Key | Action |
|---|---|
| `W` `A` `S` `D` | Move |
| `Mouse` | Look around |
| `Space` | Move up |
| `Shift` | Move down |
| `Tab` | Sprint (5× speed) |
| `Scroll` | Adjust movement speed |
| `Esc` | Toggle cursor lock |

---

## 🗺️ Roadmap

- [ ] 🤖 Neural Engine / CoreML integration (ANE upscaling, denoising)
- [ ] 🏗️ Entity-Component-System architecture
- [ ] 🔊 Spatial audio
- [ ] 🌑 Shadow mapping (cascaded shadow maps)
- [ ] 🖼️ Texture atlas support
- [ ] 🔦 Ray tracing (Metal ray tracing API)
- [ ] 💾 World persistence (save/load)
- [ ] 🌊 Volumetric fog & clouds

---

## 📄 License

```
Copyright 2026 plagness

Licensed under the Apache License, Version 2.0
```

See [LICENSE](LICENSE) for the full text.
