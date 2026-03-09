# Shaders

[← Back to README](../README.md)

## Overview

All shaders are written in Metal Shading Language. The project contains 7 `.metal` files + 1 bridging header (`ShaderTypes.h`).

## Shader Map

| Shader | File | Type | Purpose |
|---|---|---|---|
| `gbuffer_vertex` | GBufferVertex.metal | Vertex | Transform packed verts + ChunkInfo → world space |
| `gbuffer_fragment` | GBufferFragment.metal | Fragment | Pack G-Buffer (albedo, normal, emission, depth) |
| `deferred_lighting_vertex` | DeferredLighting.metal | Vertex | Fullscreen triangle (3 vertices) |
| `deferred_lighting_fragment` | DeferredLighting.metal | Fragment | PBR Cook-Torrance with 16 lights + sun |
| `water_vertex` | WaterShader.metal | Vertex | Water surface animation |
| `water_fragment` | WaterShader.metal | Fragment | Water transparency + reflection |
| `particle_vertex` | ParticleShaders.metal | Vertex | Billboard particles from compute buffer |
| `particle_fragment` | ParticleShaders.metal | Fragment | Particle glow (additive) |
| `particle_simulate` | ParticleShaders.metal | Compute | Physics simulation (gravity, wind, lifetime) |
| `terrain_generate` | VoxelTerrainGen.metal | Compute | GPU Perlin noise + biomes + caves |
| `bloom_extract` | PostProcess.metal | Compute | Bright pixel extraction |
| `bloom_downsample` | PostProcess.metal | Compute | Kawase 5-tap blur (down) |
| `bloom_upsample` | PostProcess.metal | Compute | Kawase 9-tap tent filter (up) |
| `composite_vertex` | PostProcess.metal | Vertex | Fullscreen triangle |
| `composite_fragment` | PostProcess.metal | Fragment | Tone mapping + bloom blend |

## PBR Lighting

Cook-Torrance microfacet BRDF:

```
f(l, v) = D(h) · G(l, v) · F(v, h)  /  (4 · NdotL · NdotV)
```

### Distribution (D) — GGX/Trowbridge-Reitz

```metal
float a2 = roughness * roughness;
float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
float D = a2 / (π * denom * denom);
```

### Geometry (G) — Smith with Schlick-GGX

```metal
float k = (roughness + 1)² / 8;
float G1 = NdotV / (NdotV * (1 - k) + k);
float G2 = NdotL / (NdotL * (1 - k) + k);
float G = G1 * G2;
```

### Fresnel (F) — Schlick approximation

```metal
float3 F0 = mix(float3(0.04), albedo, metallic);
float3 F = F0 + (1 - F0) * pow(1 - HdotV, 5);
```

### Final Composition

```metal
float3 kD = (1.0 - F) * (1.0 - metallic);
float3 Lo = (kD * albedo / π + specular) * lightColor * NdotL;
```

### Light Sources

**Directional Sun:**
- Direction: `normalize(0.4, 0.8, 0.3)`
- Color: `(1.4, 1.3, 1.1)` — warm, high intensity

**16 Point Lights:**
- Colors: HSV rainbow (`hue = i/16`)
- Positions: orbit around camera at varying radii (25–60 blocks)
- Heights: 8–24 blocks above camera
- Intensity: 1.2–2.0 with temporal animation
- Radius: 20 blocks each
- Attenuation: smooth falloff (`1.0 - smoothstep`)

**Hemispherical Ambient:**
```metal
float3 ambientTop    = float3(0.12, 0.15, 0.25);
float3 ambientBottom = float3(0.05, 0.04, 0.03);
float3 ambient = mix(ambientBottom, ambientTop, N.y * 0.5 + 0.5) * albedo;
```

**Atmospheric Fog:**
- Distance fog: 600–1,800 block range
- Height fog: density based on Y coordinate
- Gradient: horizon `(0.55, 0.62, 0.75)` → zenith `(0.35, 0.45, 0.65)`

## Terrain Generation (Compute)

GPU terrain runs on compute shaders. Each thread handles one XZ column (all 16 Y values):

- **Threadgroup:** 16×16 = 256 threads
- **Noise:** PCG hash-based Perlin noise (2D and 3D)
- **Fade function:** `t³(10t² - 15t + 6)` (Hermite smoothstep)

**Parameters:**
```
Sea level:         32
Base height:       40
Height variation:  30.0
Terrain scale:     0.008  (1/125 blocks)
Detail scale:      0.04   (1/25 blocks)
Cave scale:        0.05   (1/20 blocks)
Cave threshold:    0.72
```

**6 Biomes:** Ocean, Plains, Forest, Desert, Mountains, Tundra — selected via noise-based blending weights with smooth transitions.

## Post-Processing

### Bloom Pipeline

1. **Extract** — threshold bright pixels from HDR, write to half-res texture
2. **Downsample** — Dual Kawase 5-tap filter, 4 cascading levels
3. **Upsample** — Dual Kawase 9-tap tent filter, back up through levels
4. **Composite** — blend bloom with HDR, apply ACES tone mapping

### ACES Filmic Tone Mapping

```metal
float3 tonemap(float3 x) {
    float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}
```

## Vertex Format

```
PackedVoxelVertex (16 bytes)
├── position    packed_half3    6 bytes  — local [0..16]
├── normalIdx   uint8_t         1 byte   — 0..5 for ±X/±Y/±Z
├── _pad0       uint8_t         1 byte
├── uv          packed_half2    4 bytes
└── color       uint8_t × 4    4 bytes  — RGBA8
```

The vertex shader decodes `normalIdx` from a lookup table of 6 directions and reconstructs world position by adding `ChunkInfo.worldOrigin`.

## ShaderTypes.h

The bridging header defines buffer/texture indices and shared structs between Swift and Metal:

- `BufferIndexVertices`, `BufferIndexUniforms`, `BufferIndexLights`, `BufferIndexChunkInfo`
- `TextureIndexAlbedo`, `TextureIndexNormal`, etc.
- `FrameUniforms` — viewProjection matrix, camera position, time, light count, screen size
- `LightData` — position, color, radius, intensity
- `ChunkInfo` — world origin offset per chunk instance
