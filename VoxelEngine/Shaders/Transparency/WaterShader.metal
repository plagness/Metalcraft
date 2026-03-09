#include <metal_stdlib>
using namespace metal;

#include "../Common/ShaderTypes.h"

// ============================================================================
// WATER RENDERING — Semi-transparent with animated waves.
//
// On TBDR: Blending with the existing framebuffer is done in tile memory.
// Each overlapping transparent fragment blends FOR FREE (no DRAM read-modify-write).
// On IMR: Each transparent fragment = 1 DRAM read + blend + 1 DRAM write.
// ============================================================================

struct WaterVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 uv;
    float4 color;
};

vertex WaterVertexOut water_vertex(
    const device VoxelVertex* vertices [[buffer(BufferIndexVertices)]],
    constant FrameUniforms& uniforms  [[buffer(BufferIndexUniforms)]],
    uint vid [[vertex_id]]
) {
    VoxelVertex vin = vertices[vid];

    WaterVertexOut out;
    float3 pos = vin.position;

    // Animated wave displacement (only on top faces)
    if (vin.normal.y > 0.5) {
        float wave1 = sin(pos.x * 0.8 + uniforms.time * 1.5) * 0.08;
        float wave2 = sin(pos.z * 1.2 + uniforms.time * 1.1) * 0.06;
        float wave3 = sin((pos.x + pos.z) * 0.5 + uniforms.time * 0.8) * 0.04;
        pos.y += wave1 + wave2 + wave3 - 0.15; // Slight offset below block top
    }

    out.position = uniforms.viewProjectionMatrix * float4(pos, 1.0);
    out.worldPosition = pos;
    out.worldNormal = vin.normal;
    out.uv = float2(pos.x, pos.z) * 0.1; // World-space UV for seamless tiling
    out.color = vin.color;

    return out;
}

fragment float4 water_fragment(
    WaterVertexOut in [[stage_in]],
    constant FrameUniforms& uniforms [[buffer(BufferIndexUniforms)]]
) {
    float3 N = normalize(in.worldNormal);
    float3 V = normalize(uniforms.cameraPosition - in.worldPosition);

    // Fresnel effect — more reflective at grazing angles
    float fresnel = pow(1.0 - max(dot(N, V), 0.0), 3.0);
    fresnel = mix(0.1, 0.8, fresnel);

    // Water base color with depth-dependent tint
    float3 shallowColor = float3(0.15, 0.45, 0.65);
    float3 deepColor = float3(0.05, 0.15, 0.35);
    float depthFactor = clamp(in.worldPosition.y / 32.0, 0.0, 1.0);
    float3 waterColor = mix(deepColor, shallowColor, depthFactor);

    // Sun reflection
    float3 sunDir = normalize(float3(0.4, 0.8, 0.3));
    float3 R = reflect(-sunDir, N);
    float specular = pow(max(dot(V, R), 0.0), 128.0) * 0.8;

    // Animated caustic-like pattern
    float caustic = sin(in.worldPosition.x * 3.0 + uniforms.time * 2.0)
                  * sin(in.worldPosition.z * 3.0 + uniforms.time * 1.7) * 0.1;

    float3 finalColor = waterColor + float3(specular) + caustic;

    // Transparency: more opaque from above, more transparent at edges
    float alpha = mix(0.4, 0.7, fresnel);

    return float4(finalColor, alpha);
}
