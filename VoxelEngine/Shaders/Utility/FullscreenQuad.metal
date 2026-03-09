#include <metal_stdlib>
using namespace metal;

#include "../Common/ShaderTypes.h"

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

/// Fullscreen triangle (single triangle covers entire screen — more efficient than quad).
vertex FullscreenOut fullscreen_vertex(uint vid [[vertex_id]]) {
    FullscreenOut out;
    // Generate a single triangle that covers clip space [-1,1]
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv.y = 1.0 - out.uv.y; // Flip Y for Metal texture coords
    return out;
}

/// Simple debug overlay vertex shader
vertex float4 debug_vertex(
    const device DebugVertex* vertices [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    DebugVertex v = vertices[vid];
    return float4(v.position, 0.0, 1.0);
}

/// Debug overlay fragment — solid color
fragment float4 debug_fragment(
    float4 position [[stage_in]]
) {
    return float4(1.0, 1.0, 1.0, 0.8);
}
