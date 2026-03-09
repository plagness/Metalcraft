#include <metal_stdlib>
using namespace metal;

#include "../Common/ShaderTypes.h"

// Packed vertex format: 16 bytes (vs 48 for VoxelVertex)
// Positions are LOCAL to chunk [0..16], world origin comes from ChunkInfo
struct PackedVoxelVertex {
    packed_half3 position;   // 6 bytes — local position within chunk
    uint8_t      normalIdx;  // 1 byte  — normal index (0..5 = ±X,±Y,±Z)
    uint8_t      _pad0;      // 1 byte  — alignment
    packed_half2 uv;         // 4 bytes
    uint8_t      r, g, b, a; // 4 bytes — RGBA8 color
};                           // = 16 bytes total

// Normal decode table — 6 axis-aligned directions
constant float3 kNormals[6] = {
    float3( 1, 0, 0),  // 0: +X
    float3(-1, 0, 0),  // 1: -X
    float3( 0, 1, 0),  // 2: +Y
    float3( 0,-1, 0),  // 3: -Y
    float3( 0, 0, 1),  // 4: +Z
    float3( 0, 0,-1),  // 5: -Z
};

struct GBufferVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 uv;
    float4 color;
};

vertex GBufferVertexOut gbuffer_vertex(
    const device PackedVoxelVertex* vertices [[buffer(BufferIndexVertices)]],
    const device ChunkInfo*         chunkInfos [[buffer(BufferIndexChunkInfo)]],
    constant FrameUniforms&         uniforms  [[buffer(BufferIndexUniforms)]],
    uint vid [[vertex_id]],
    uint iid [[instance_id]]
) {
    PackedVoxelVertex vin = vertices[vid];
    ChunkInfo info = chunkInfos[iid];

    // Decode local position → world position
    float3 localPos = float3(vin.position);
    float3 worldPos = info.worldOrigin + localPos;

    GBufferVertexOut out;
    out.position = uniforms.viewProjectionMatrix * float4(worldPos, 1.0);
    out.worldPosition = worldPos;
    out.worldNormal = kNormals[min(uint(vin.normalIdx), 5u)];
    out.uv = float2(vin.uv);
    out.color = float4(float(vin.r), float(vin.g), float(vin.b), float(vin.a)) / 255.0;

    return out;
}
