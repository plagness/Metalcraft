#include <metal_stdlib>
using namespace metal;

#include "../Common/ShaderTypes.h"

struct GBufferVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 uv;
    float4 color;
};

/// G-buffer output — writes to color attachments that stay in tile memory (TBDR).
/// storeAction = .dontCare means these NEVER touch DRAM.
/// The deferred lighting pass reads them via [[color(n)]] in the SAME render pass.
struct GBufferOut {
    float4 albedoMetallic [[color(0)]];    // RGB=albedo, A=metallic
    float4 normalRoughness [[color(1)]];   // RGB=normal*0.5+0.5, A=roughness
    float4 emissionDepth [[color(2)]];     // RGB=emission, A=NDC depth (rgba16Float)
};

fragment GBufferOut gbuffer_fragment(
    GBufferVertexOut in [[stage_in]],
    constant FrameUniforms& uniforms [[buffer(BufferIndexUniforms)]]
) {
    GBufferOut out;

    float3 N = normalize(in.worldNormal);
    float3 albedo = in.color.rgb;
    float metallic = 0.0;
    float roughness = 0.85;
    float3 emission = float3(0.0);

    // Detect emissive blocks by high brightness
    float brightness = dot(albedo, float3(0.299, 0.587, 0.114));
    if (brightness > 0.9) {
        emission = albedo * 2.0;
    }

    // Pack G-buffer — depth stored in alpha for single-pass deferred
    out.albedoMetallic = float4(albedo, metallic);
    out.normalRoughness = float4(N * 0.5 + 0.5, roughness);
    out.emissionDepth = float4(emission, in.position.z);  // NDC depth [0,1]

    return out;
}
