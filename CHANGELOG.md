# Changelog

## 26.3.10.1

Initial public release.

- Single-pass deferred rendering optimized for Apple Silicon GPU
- PBR Cook-Torrance lighting (GGX + Smith + Schlick)
- GPU compute terrain generation (Perlin noise, 6 biomes)
- Greedy meshing with 16-byte packed vertices
- 4-level LOD system (step 1/2/4/8)
- Mega-buffer architecture (128 MB vertex + 64 MB index)
- Indirect Command Buffer (4,500 draws → 1 GPU command)
- 8,192 GPU-simulated particles
- Bloom post-processing (Kawase blur, 4 mip levels)
- ACES filmic tone mapping
- Water with forward transparency
- 27 block types with PBR properties
- Frustum culling with caching
- Triple buffering
- Ring-based chunk streaming (up to 100K loaded)
