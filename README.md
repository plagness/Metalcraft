<div align="right">

🇬🇧 | [🇷🇺](RU.md)

</div>

<div align="center">

# Metalcraft

Voxel engine built from scratch in Swift + Metal for Apple Silicon

An experiment in seeing how far you can push a single M-series chip with zero external dependencies

<br>

[![Version](https://img.shields.io/badge/version-26.3.10.1-blue.svg)](https://github.com/plagness/Metalcraft/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?logo=swift&logoColor=white)](https://swift.org)
[![Metal](https://img.shields.io/badge/Metal-API-8A8A8A.svg?logo=apple&logoColor=white)](https://developer.apple.com/metal/)
[![macOS](https://img.shields.io/badge/macOS-14.0+-000000.svg?logo=macos&logoColor=white)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1+-FF3B30.svg?logo=apple&logoColor=white)](https://support.apple.com/en-us/116943)
[![License](https://img.shields.io/badge/license-Apache_2.0-green.svg)](LICENSE)

<br>

![Screenshot](Screenshots/2026-03-10.png)

<br>

[Architecture](docs/architecture.md) · [Performance](docs/performance.md) · [Shaders](docs/shaders.md) · [Chunk System](docs/chunk-system.md) · [Changelog](CHANGELOG.md)

</div>

---

## ✨ Features

### 🎨 Rendering
- Single-pass deferred rendering optimized for Apple Silicon GPU
- PBR Cook-Torrance lighting (GGX + Smith + Schlick)
- G-Buffer stored entirely in on-chip tile memory — never hits DRAM
- 16 animated point lights + directional sun + hemispherical ambient
- Bloom post-processing (Kawase blur, 4 mip levels)
- ACES filmic tone mapping
- Atmospheric distance + height fog
- Water with forward transparency

### 🌍 World
- 16×16×16 voxel chunks, view distance 64 chunks (1,024 blocks)
- Up to 100,000 loaded chunks, 4,500 rendered per frame
- GPU compute terrain generation — Perlin noise, 10–50× faster than CPU
- 6 biomes with smooth blending: Ocean, Plains, Forest, Desert, Mountains, Tundra
- 27 block types with PBR properties (roughness, metallic, emission, transparency)
- Cave carving and tree placement

### ⚡ Performance
- Greedy meshing — merges adjacent faces into larger quads
- 16-byte packed vertex format (vs 48 naive)
- Mega-buffer architecture: 128 MB vertex + 64 MB index, single bind per frame
- Indirect Command Buffer: 4,500 draws → 1 GPU command
- 4-level LOD system (step 1/2/4/8 based on distance)
- Frustum culling with caching
- Triple buffering (3 frames in-flight)

### ✨ Effects
- 8,192 GPU-simulated particles (compute shader)
- Bloom (Kawase 5-tap/9-tap, 4 mip cascade)
- Vignette

### 🤖 Neural Engine
- Prepared `NeuralEngine/` module for CoreML / ANE integration
- Planned: ML upscaling, denoising, LOD prediction
- [Full details →](docs/neural-engine.md)

---

## 🚀 Quick Start

```bash
git clone https://github.com/plagness/Metalcraft.git
cd Metalcraft
open VoxelEngine.xcodeproj
# Cmd+R to build and run
```

Or regenerate with XcodeGen:
```bash
brew install xcodegen
xcodegen generate
open VoxelEngine.xcodeproj
```

### 🎮 Controls

| Key | Action |
|---|---|
| `W` `A` `S` `D` | Move |
| `Mouse` | Look around |
| `Space` | Up |
| `Shift` | Down |
| `Tab` | Sprint (5×) |
| `Scroll` | Adjust speed |
| `Esc` | Toggle cursor lock |

---

## 📋 Requirements

| | Minimum |
|---|---|
| **OS** | macOS 14.0 (Sonoma) |
| **Hardware** | Apple Silicon (M1+) |
| **GPU** | Metal GPU Family Apple 7+ |
| **Xcode** | 15.0+ |
| **Swift** | 5.9 |

> ⚠️ Intel Macs are not supported — requires Apple Silicon unified memory.

## 🧰 Frameworks

`Metal` · `MetalKit` · `simd` · `CoreGraphics` · `CoreText` · `Cocoa` · `QuartzCore` · `Foundation`

Zero external dependencies. No SPM. No CocoaPods. No Carthage.

---

## 📁 Structure

```
Metalcraft/
├── VoxelEngine/
│   ├── App/              Entry point, window, view controller
│   ├── Core/             Time tracking
│   ├── Input/            Keyboard + mouse FPS controls
│   ├── Math/             Noise, frustum culling
│   ├── Renderer/         Metal renderer, camera, mega-buffer allocator
│   ├── Compute/          GPU terrain generation
│   ├── Voxel/            Chunks, block types, greedy mesher, water
│   ├── Debug/            FPS overlay
│   ├── Shaders/
│   │   ├── Common/       ShaderTypes.h (Swift↔Metal bridging)
│   │   ├── Deferred/     G-Buffer + PBR lighting
│   │   ├── Transparency/ Water forward pass
│   │   ├── Particles/    GPU compute + billboard render
│   │   ├── PostProcess/  Bloom, tone mapping
│   │   ├── Voxel/        GPU terrain compute
│   │   └── Utility/      Fullscreen triangle
│   ├── NeuralEngine/     [Planned] CoreML / ANE
│   └── ECS/              [Planned] Entity-Component-System
├── docs/                 Technical documentation
├── Screenshots/          Build screenshots
├── project.yml           XcodeGen definition
└── VoxelEngine.xcodeproj Ready to build
```

---

## 🗺️ Roadmap

- [ ] Neural Engine / CoreML (ANE upscaling, denoising)
- [ ] Entity-Component-System
- [ ] Spatial audio
- [ ] Shadow mapping (cascaded)
- [ ] Texture atlas
- [ ] Ray tracing (Metal RT API)
- [ ] World persistence
- [ ] Volumetric fog & clouds

## 📖 Documentation

- [Architecture](docs/architecture.md) — render pipeline, deferred rendering, tile memory
- [Performance](docs/performance.md) — metrics, benchmarks, bandwidth analysis
- [Shaders](docs/shaders.md) — Metal shaders, PBR, bloom, particles
- [Chunk System](docs/chunk-system.md) — mega-buffer, ICB, greedy meshing, LOD
- [Neural Engine](docs/neural-engine.md) — CoreML / ANE integration plans

---

## 📄 License

```
Copyright 2026 plagness
Licensed under the Apache License, Version 2.0
```

See [LICENSE](LICENSE) for full text.
