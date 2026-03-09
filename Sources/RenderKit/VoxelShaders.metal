#include <metal_stdlib>
using namespace metal;

struct MeshVertex {
    float3 position;
    float3 normal;
};

struct InstanceData {
    float3 translation;
    float4 color;
};

struct FrameUniforms {
    float4x4 viewProjection;
    float3 lightDirection;
    float padding;
};

struct RasterizerData {
    float4 position [[position]];
    float4 color;
    float lighting;
};

vertex RasterizerData voxel_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant MeshVertex *vertices [[buffer(0)]],
    constant InstanceData *instances [[buffer(1)]],
    constant FrameUniforms &uniforms [[buffer(2)]]
) {
    MeshVertex inVertex = vertices[vertexID];
    InstanceData instance = instances[instanceID];

    float3 worldPosition = inVertex.position + instance.translation;
    float3 lightDirection = normalize(uniforms.lightDirection);
    float lighting = 0.32 + 0.68 * saturate(dot(inVertex.normal, lightDirection));

    RasterizerData out;
    out.position = uniforms.viewProjection * float4(worldPosition, 1.0);
    out.color = instance.color;
    out.lighting = lighting;
    return out;
}

fragment half4 voxel_fragment(RasterizerData in [[stage_in]]) {
    return half4(half3(in.color.rgb * in.lighting), half(in.color.a));
}
