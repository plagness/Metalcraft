#include <metal_stdlib>
using namespace metal;

#include "../Common/ShaderTypes.h"

// ============================================================================
// GPU PARTICLE SYSTEM — compute simulation + billboard rendering.
//
// On Apple Silicon TBDR:
// - Compute and render share the SAME memory (UMA, zero-copy)
// - Overdraw from thousands of translucent particles is nearly free
//   because TBDR resolves in tile memory (no read-modify-write to DRAM)
// - On IMR, each overlapping particle would cause DRAM read + blend + write
// ============================================================================

struct Particle {
    float3 position;
    float  life;         // 0..1, 0=dead
    float3 velocity;
    float  size;
    float4 color;
};

struct ParticleConfig {
    float3 emitterPosition;
    float  deltaTime;
    float3 gravity;
    float  spawnRate;
    float3 windDirection;
    float  windStrength;
    float  emitterRadius;
    uint   maxParticles;
    uint   frameIndex;
    float  _padding;
};

// PCG-style hash — much better distribution than LCG
static uint pcg_hash(uint input) {
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

static float rand_float(thread uint& seed) {
    seed = pcg_hash(seed);
    return float(seed) / float(0xFFFFFFFFu);
}

// === COMPUTE: Simulate particles ===
kernel void particle_simulate(
    device Particle* particles [[buffer(0)]],
    constant ParticleConfig& config [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= config.maxParticles) return;

    Particle p = particles[id];

    if (p.life <= 0.0) {
        // Seed from particle id + frame for unique random per particle per frame
        uint seed = id ^ (config.frameIndex * 1664525u + 1013904223u);

        float r1 = rand_float(seed);
        float r2 = rand_float(seed);
        float r3 = rand_float(seed);
        float r4 = rand_float(seed);
        float r5 = rand_float(seed);

        // Stagger respawn: each particle has a different spawn probability
        // so they don't all appear at once
        float spawnChance = config.spawnRate * config.deltaTime;
        spawnChance = clamp(spawnChance, 0.0, 0.15); // Max 15% per frame
        if (r4 > spawnChance) return;

        // Spread spawn across a wide area above camera
        float angle = r1 * 6.28318;
        float dist = sqrt(r2) * config.emitterRadius; // sqrt for uniform disk
        p.position = config.emitterPosition + float3(
            cos(angle) * dist,
            r3 * 10.0 + 5.0,   // 5-15 units above emitter
            sin(angle) * dist
        );

        // Varied fall speeds for natural look
        float fallSpeed = -12.0 - r5 * 15.0;
        p.velocity = float3(
            (r1 - 0.5) * 2.0,  // Slight horizontal drift
            fallSpeed,
            (r3 - 0.5) * 2.0
        );

        // Randomized lifetime so particles die at different times
        p.life = 0.5 + r5 * 0.8;
        p.size = 0.04 + r2 * 0.06;
        p.color = float4(0.6, 0.7, 0.85, 0.2 + r3 * 0.15);
    } else {
        // Update living particles
        p.velocity += config.gravity * config.deltaTime;
        p.velocity += config.windDirection * config.windStrength * config.deltaTime;
        p.position += p.velocity * config.deltaTime;
        p.life -= config.deltaTime * 0.4;
        p.color.a = clamp(p.life * 0.4, 0.0, 0.35); // Subtle fade
    }

    particles[id] = p;
}

// === RENDER: Billboard quads ===

struct ParticleVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex ParticleVertexOut particle_vertex(
    const device Particle* particles [[buffer(0)]],
    constant FrameUniforms& uniforms [[buffer(BufferIndexUniforms)]],
    uint vid [[vertex_id]],
    uint iid [[instance_id]]
) {
    Particle p = particles[iid];

    ParticleVertexOut out;

    if (p.life <= 0.0) {
        out.position = float4(0, 0, -2, 1); // Off-screen
        out.uv = float2(0);
        out.color = float4(0);
        return out;
    }

    // Billboard quad (2 triangles, 6 vertices per particle)
    float2 offsets[6] = {
        float2(-1, -1), float2(1, -1), float2(1, 1),
        float2(-1, -1), float2(1, 1), float2(-1, 1)
    };
    float2 uvs[6] = {
        float2(0, 0), float2(1, 0), float2(1, 1),
        float2(0, 0), float2(1, 1), float2(0, 1)
    };

    float2 offset = offsets[vid % 6];
    out.uv = uvs[vid % 6];

    // Camera-facing billboard
    float3 camRight = float3(uniforms.inverseViewMatrix.columns[0].xyz);
    float3 camUp = float3(0, 1, 0); // Rain streaks stay vertical

    float3 worldPos = p.position
        + camRight * offset.x * p.size * 0.3
        + camUp * offset.y * p.size * 2.0; // Elongated for rain

    out.position = uniforms.viewProjectionMatrix * float4(worldPos, 1.0);
    out.color = p.color;

    return out;
}

fragment float4 particle_fragment(
    ParticleVertexOut in [[stage_in]]
) {
    // Soft rain drop shape
    float2 uv = in.uv * 2.0 - 1.0;
    float dist = length(uv);
    float alpha = smoothstep(1.0, 0.3, dist) * in.color.a;

    return float4(in.color.rgb, alpha);
}
