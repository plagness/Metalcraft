#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// MARK: - Buffer Indices
typedef enum {
    BufferIndexVertices     = 0,
    BufferIndexUniforms     = 1,
    BufferIndexLights       = 2,
    BufferIndexMaterials    = 3,
    BufferIndexInstances    = 4,
    BufferIndexChunkInfo    = 5,
} BufferIndex;

// MARK: - Texture Indices
typedef enum {
    TextureIndexAlbedo      = 0,
    TextureIndexNormal      = 1,
    TextureIndexRoughMetal  = 2,
    TextureIndexShadowMap   = 3,
    TextureIndexAO          = 4,
    TextureIndexSkybox      = 5,
} TextureIndex;

// MARK: - Vertex Attribute Indices
typedef enum {
    VertexAttributePosition  = 0,
    VertexAttributeNormal    = 1,
    VertexAttributeUV        = 2,
    VertexAttributeColor     = 3,
} VertexAttribute;

// MARK: - Frame Uniforms (per-frame constants)
typedef struct {
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4x4 viewProjectionMatrix;
    simd_float4x4 inverseViewMatrix;
    simd_float4x4 inverseProjectionMatrix;
    simd_float4x4 previousViewProjectionMatrix;
    simd_float4x4 viewProjectionMatrixJittered;
    simd_float3   cameraPosition;
    float         time;
    simd_float2   jitterOffset;
    simd_float2   screenSize;
    uint32_t      frameIndex;
    uint32_t      lightCount;
    float         nearPlane;
    float         farPlane;
} FrameUniforms;

// MARK: - Vertex Formats
typedef struct {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 uv;
    simd_float4 color;
} VoxelVertex;

// MARK: - Light Types
typedef enum {
    LightTypePoint       = 0,
    LightTypeSpot        = 1,
    LightTypeDirectional = 2,
} LightType;

typedef struct {
    simd_float3 position;
    float       radius;
    simd_float3 color;
    float       intensity;
    simd_float3 direction;
    float       innerConeAngle;
    float       outerConeAngle;
    uint32_t    type;
    uint32_t    castsShadow;
    uint32_t    _padding;
} LightData;

// MARK: - Material
typedef struct {
    simd_float4 albedoColor;
    float       roughness;
    float       metallic;
    float       sssRadius;
    uint32_t    flags;        // bit 0: isSSS, bit 1: isEmissive, bit 2: isTransparent
    uint32_t    albedoTexture;
    uint32_t    normalTexture;
    uint32_t    roughMetalTexture;
    uint32_t    _padding;
} MaterialData;

// MARK: - Instance Data (per-chunk, legacy)
typedef struct {
    simd_float4x4 modelMatrix;
    uint32_t      materialIndex;
    uint32_t      _padding0;
    uint32_t      _padding1;
    uint32_t      _padding2;
} InstanceData;

// MARK: - Chunk Info (per-chunk, indexed by [[instance_id]] via baseInstance)
typedef struct {
    simd_float3 worldOrigin;    // chunk world-space origin = chunkPos * CHUNK_SIZE
    uint32_t    _padding;
} ChunkInfo;

// MARK: - Debug Vertex (for overlay)
typedef struct {
    simd_float2 position;
    simd_float2 uv;
    simd_float4 color;
} DebugVertex;

#endif /* ShaderTypes_h */
