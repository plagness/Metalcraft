#include <metal_stdlib>
using namespace metal;

#include "../Common/ShaderTypes.h"

// ============================================================================
// SINGLE-PASS DEFERRED LIGHTING — reads G-buffer via [[color(n)]] (programmable blending).
//
// On Apple Silicon TBDR, the G-buffer lives exclusively in tile memory (SRAM).
// This shader reads it with ZERO DRAM bandwidth — the data was written by the
// G-buffer fragment shader in the SAME render pass and still sits in tile memory.
//
// G-buffer attachments have storeAction = .dontCare → never stored to DRAM.
// Only the HDR result (color[3]) exits tile memory.
//
// Bandwidth saved vs separate passes: ~58 MB/frame at 1080p.
// ============================================================================

// PBR utilities
static float distributionGGX(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * denom * denom + 0.0001);
}

static float geometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

static float geometrySmith(float NdotV, float NdotL, float roughness) {
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

static float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Reconstruct world position from depth
static float3 reconstructWorldPos(float2 uv, float depth,
                                  constant FrameUniforms& uniforms) {
    float2 ndc = uv * 2.0 - 1.0;
    ndc.y = -ndc.y;
    float4 clipPos = float4(ndc, depth, 1.0);
    float4 viewPos = uniforms.inverseProjectionMatrix * clipPos;
    viewPos /= viewPos.w;
    float4 worldPos = uniforms.inverseViewMatrix * viewPos;
    return worldPos.xyz;
}

// Fullscreen triangle vertex shader
struct LightingVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex LightingVertexOut deferred_lighting_vertex(uint vid [[vertex_id]]) {
    LightingVertexOut out;
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

/// G-buffer data read from tile memory via programmable blending.
/// These match the color attachments written by the G-buffer fill pass.
struct GBufferInput {
    float4 albedoMetallic [[color(0)]];
    float4 normalRoughness [[color(1)]];
    float4 emissionDepth [[color(2)]];
};

/// Output to color attachment 3 (HDR).
struct LightingOutput {
    float4 hdr [[color(3)]];
};

/// Deferred lighting fragment — reads G-buffer from tile memory via [[color(n)]].
/// Zero DRAM bandwidth for G-buffer reads on Apple Silicon TBDR.
fragment LightingOutput deferred_lighting_fragment(
    LightingVertexOut in [[stage_in]],
    GBufferInput gbuffer,
    constant FrameUniforms& uniforms [[buffer(BufferIndexUniforms)]],
    constant LightData* lights [[buffer(BufferIndexLights)]]
) {
    LightingOutput out;

    // Read G-buffer from tile memory (zero bandwidth!)
    float4 albedoMetallic = gbuffer.albedoMetallic;
    float4 normalRoughness = gbuffer.normalRoughness;
    float3 emission = gbuffer.emissionDepth.rgb;
    float depth = gbuffer.emissionDepth.a;

    // Early exit for sky pixels
    if (depth >= 0.9999) {
        float t = in.uv.y;
        float3 skyTop = float3(0.2, 0.3, 0.55);
        float3 skyHorizon = float3(0.55, 0.62, 0.75);
        out.hdr = float4(mix(skyHorizon, skyTop, t), 1.0);
        return out;
    }

    // Unpack G-buffer
    float3 albedo = albedoMetallic.rgb;
    float metallic = albedoMetallic.a;
    float3 N = normalize(normalRoughness.rgb * 2.0 - 1.0);
    float roughness = normalRoughness.a;

    // Reconstruct world position from depth
    float3 worldPos = reconstructWorldPos(in.uv, depth, uniforms);
    float3 V = normalize(uniforms.cameraPosition - worldPos);
    float NdotV = max(dot(N, V), 0.001);

    // Base reflectance
    float3 F0 = mix(float3(0.04), albedo, metallic);

    // === Directional sun light ===
    float3 sunDir = normalize(float3(0.4, 0.8, 0.3));
    float3 sunColor = float3(1.4, 1.3, 1.1);
    float NdotL_sun = max(dot(N, sunDir), 0.0);
    float3 H_sun = normalize(V + sunDir);

    float D_sun = distributionGGX(N, H_sun, roughness);
    float G_sun = geometrySmith(NdotV, NdotL_sun, roughness);
    float3 F_sun = fresnelSchlick(max(dot(H_sun, V), 0.0), F0);

    float3 specular_sun = (D_sun * G_sun * F_sun) / (4.0 * NdotV * NdotL_sun + 0.001);
    float3 kD_sun = (1.0 - F_sun) * (1.0 - metallic);
    float3 Lo_sun = (kD_sun * albedo / 3.14159265 + specular_sun) * sunColor * NdotL_sun;

    // === Point / Spot lights ===
    float3 Lo_lights = float3(0.0);
    uint lightCount = uniforms.lightCount;

    for (uint i = 0; i < lightCount && i < 128; i++) {
        LightData light = lights[i];
        float3 lightPos = light.position;
        float3 lightColor = light.color * light.intensity;
        float lightRadius = light.radius;

        float3 L = lightPos - worldPos;
        float dist = length(L);

        if (dist > lightRadius) continue;
        L /= dist;

        float attenuation = 1.0 - smoothstep(lightRadius * 0.7, lightRadius, dist);
        attenuation *= attenuation;

        if (light.type == LightTypeSpot) {
            float theta = dot(L, normalize(-light.direction));
            float epsilon = light.innerConeAngle - light.outerConeAngle;
            float spotIntensity = clamp((theta - light.outerConeAngle) / epsilon, 0.0, 1.0);
            attenuation *= spotIntensity;
        }

        float NdotL = max(dot(N, L), 0.0);
        float3 H = normalize(V + L);

        float D = distributionGGX(N, H, roughness);
        float G = geometrySmith(NdotV, NdotL, roughness);
        float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

        float3 specular = (D * G * F) / (4.0 * NdotV * NdotL + 0.001);
        float3 kD = (1.0 - F) * (1.0 - metallic);

        Lo_lights += (kD * albedo / 3.14159265 + specular) * lightColor * NdotL * attenuation;
    }

    // === Ambient (hemispherical) ===
    float3 ambientTop = float3(0.12, 0.15, 0.25);
    float3 ambientBottom = float3(0.05, 0.04, 0.03);
    float3 ambient = mix(ambientBottom, ambientTop, N.y * 0.5 + 0.5) * albedo;

    float3 color = ambient + Lo_sun + Lo_lights + emission;

    // Atmospheric distance fog
    float viewDist = length(worldPos - uniforms.cameraPosition);
    float fogStart = 600.0;
    float fogEnd   = 1800.0;
    float fogFactor = smoothstep(fogStart, fogEnd, viewDist);

    float heightFog = 1.0 - saturate((worldPos.y - 10.0) / 80.0);
    fogFactor = max(fogFactor, heightFog * 0.05);

    float3 fogColorHorizon = float3(0.55, 0.62, 0.75);
    float3 fogColorZenith = float3(0.35, 0.45, 0.65);
    float upFactor = saturate(normalize(worldPos - uniforms.cameraPosition).y + 0.2);
    float3 fogColor = mix(fogColorHorizon, fogColorZenith, upFactor);
    color = mix(color, fogColor, fogFactor);

    out.hdr = float4(color, 1.0);
    return out;
}
