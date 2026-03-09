# Neural Engine

[← Back to README](../README.md)

> **Status:** Architecture prepared, integration in progress

## Overview

The project includes a dedicated `NeuralEngine/` module designed for Apple Neural Engine (ANE) integration via CoreML.

The `NeuralEngine/Models/` directory is prepared for CoreML model files (`.mlmodelc`).

## Why ANE for a Voxel Engine?

Apple Silicon's Neural Engine (up to 38 TOPS on M4) runs **independently from the GPU**. This means ML inference can happen **in parallel** with GPU rendering — effectively free compute for visual quality improvements.

```
GPU: [  Render Frame N  ][  Render Frame N+1  ]
ANE: [  Upscale N-1  ][  Denoise N  ][  Upscale N  ]
                  ↑ runs concurrently, no GPU contention
```

## Planned Capabilities

### ML-Based Upscaling

Render at lower resolution (e.g., 720p), upscale via ANE to display resolution (1440p/4K). Similar concept to DLSS (NVIDIA) or FSR (AMD), but running on Apple's dedicated neural hardware.

**Approach:**
- Train a lightweight super-resolution model on voxel-style imagery
- Convert to CoreML format (`.mlmodelc`)
- Run inference on ANE during the composite pass
- Temporal stability via motion vectors from the render pipeline

### Real-Time Denoising

For future ray-traced passes (shadows, reflections):
- ANE-accelerated denoiser running in parallel with GPU
- Similar to OptiX denoising but on dedicated neural hardware
- Could enable real-time ray tracing at lower sample counts

### LOD Prediction

ML-driven LOD selection based on camera trajectory:
- Predict which chunks the player will see in 0.5–1s
- Pre-load and pre-mesh at appropriate LOD before they're visible
- Reduce pop-in and improve perceived draw distance

### Terrain Enhancement

Neural-assisted detail generation:
- Low-res terrain from GPU compute → upscale detail via ANE
- ML-based biome transition smoothing
- Procedural decoration placement using learned patterns

## Integration Architecture

```
VoxelEngine/
└── NeuralEngine/
    ├── Models/           CoreML model files (.mlmodelc)
    ├── NEUpscaler.swift  [Planned] Super-resolution inference
    ├── NEDenoiser.swift  [Planned] Real-time denoising
    └── NEPredictor.swift [Planned] LOD/chunk prediction
```

The module will use `MLModel` from CoreML framework with:
- `MLComputeUnits.cpuAndNeuralEngine` — prefer ANE, fallback to CPU
- Async prediction via `MLModel.prediction(from:completionHandler:)`
- Double-buffered input/output to avoid stalls

## Hardware Requirements

| Chip | ANE TOPS | Expected Upscale Time (720p→1440p) |
|---|---|---|
| M1 | 11 | ~4ms |
| M2 | 15.8 | ~3ms |
| M3 | 18 | ~2.5ms |
| M4 | 38 | ~1.5ms |

*Estimates based on typical super-resolution model complexity. Actual performance will depend on model architecture.*
