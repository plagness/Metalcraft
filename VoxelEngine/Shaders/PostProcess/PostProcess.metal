#include <metal_stdlib>
using namespace metal;

#include "../Common/ShaderTypes.h"

// ============================================================================
// POST-PROCESSING — Bloom extraction, blur, and tone mapping.
//
// Apple Silicon advantage: compute shaders share UMA memory with render.
// No PCIe transfer or memory copy needed. Bloom blur reads/writes the same
// physical memory as the render output.
// ============================================================================

// === Bloom threshold extraction (downsamples full-res HDR → half-res bloom) ===
kernel void bloom_extract(
    texture2d<float, access::sample> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = output.get_width();
    uint h = output.get_height();
    if (gid.x >= w || gid.y >= h) return;

    // Sample from full-res HDR using UV — bilinear gives a 2x2 box filter downsample
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float4 color = input.sample(s, uv);

    float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));

    // Extract bright areas (threshold)
    float3 bloom = color.rgb * smoothstep(0.8, 1.5, brightness);
    output.write(float4(bloom, 1.0), gid);
}

// === Dual Kawase blur (down) — more efficient than Gaussian on mobile GPUs ===
kernel void bloom_downsample(
    texture2d<float, access::sample> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = output.get_width();
    uint h = output.get_height();
    if (gid.x >= w || gid.y >= h) return;

    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 texelSize = 1.0 / float2(input.get_width(), input.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(w, h);

    // Kawase downsample: 5-tap pattern
    float4 sum = input.sample(s, uv) * 4.0;
    sum += input.sample(s, uv + float2(-1, -1) * texelSize);
    sum += input.sample(s, uv + float2( 1, -1) * texelSize);
    sum += input.sample(s, uv + float2(-1,  1) * texelSize);
    sum += input.sample(s, uv + float2( 1,  1) * texelSize);
    sum /= 8.0;

    output.write(sum, gid);
}

// === Dual Kawase blur (up) — writes to separate output, no read-write hazard ===
kernel void bloom_upsample(
    texture2d<float, access::sample> input [[texture(0)]],
    texture2d<float, access::read> original [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = output.get_width();
    uint h = output.get_height();
    if (gid.x >= w || gid.y >= h) return;

    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 texelSize = 1.0 / float2(input.get_width(), input.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(w, h);

    // Kawase upsample: 9-tap tent filter
    float4 sum = float4(0);
    sum += input.sample(s, uv + float2(-1, -1) * texelSize);
    sum += input.sample(s, uv + float2( 0, -1) * texelSize) * 2.0;
    sum += input.sample(s, uv + float2( 1, -1) * texelSize);
    sum += input.sample(s, uv + float2(-1,  0) * texelSize) * 2.0;
    sum += input.sample(s, uv) * 4.0;
    sum += input.sample(s, uv + float2( 1,  0) * texelSize) * 2.0;
    sum += input.sample(s, uv + float2(-1,  1) * texelSize);
    sum += input.sample(s, uv + float2( 0,  1) * texelSize) * 2.0;
    sum += input.sample(s, uv + float2( 1,  1) * texelSize);
    sum /= 16.0;

    // Additive blend with original
    float4 orig = original.read(gid);
    output.write(orig + sum * 0.3, gid);
}

// === Final composite with tone mapping ===
struct CompositeVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex CompositeVertexOut composite_vertex(uint vid [[vertex_id]]) {
    CompositeVertexOut out;
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

// ACES filmic tone mapping (better highlight rolloff than Reinhard)
static float3 acesToneMap(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

fragment float4 composite_fragment(
    CompositeVertexOut in [[stage_in]],
    texture2d<float> hdrInput [[texture(0)]],
    texture2d<float> bloomInput [[texture(1)]],
    constant FrameUniforms& uniforms [[buffer(BufferIndexUniforms)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    float3 color = hdrInput.sample(s, in.uv).rgb;

    // Add bloom (sampled with bilinear from lower-res texture)
    float3 bloom = bloomInput.sample(s, in.uv).rgb;
    color += bloom * 0.15;

    // ACES tone mapping (handles HDR → LDR gracefully)
    color = acesToneMap(color);

    // Vignette
    float2 vc = in.uv - 0.5;
    float vignette = 1.0 - dot(vc, vc) * 0.5;
    color *= vignette;

    return float4(color, 1.0);
}
