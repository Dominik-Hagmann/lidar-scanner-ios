#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PCCloud PCCloud;
typedef struct {
    float x, y, z; /* ARKit world coordinates: metres, Y up. */
    uint8_t r, g, b, confidence;
} PCPoint;

typedef struct {
    float voxelMeters, minDepth, maxDepth;
    uint32_t maxPoints; /* 0: no configured point-count limit; caller monitors memory. */
    int32_t pixelStep;
    uint8_t minConfidence;
} PCConfig;

typedef struct {
    const void *depth;
    size_t depthRowBytes;
    int32_t width, height;
    const uint8_t *confidence;
    size_t confidenceRowBytes;
    const uint8_t *luma, *chroma;
    size_t lumaRowBytes, chromaRowBytes;
    int32_t imageWidth, imageHeight, chromaWidth, chromaHeight;
    int32_t videoRange, matrix709;
    /* Intrinsics already scaled to the depth image's pixel grid. */
    float fx, fy, cx, cy;
    const float *cameraToWorld; /* 16 floats, column-major. */
} PCFrame;

typedef struct {
    uint32_t pointCount;
    uint64_t acceptedSamples;
    int32_t atCapacity;
} PCStats;

/* Thread confinement: use one serial queue for each cloud. */
PCCloud *pc_create(PCConfig config);
void pc_destroy(PCCloud *cloud);
void pc_reset(PCCloud *cloud, PCConfig config);
/* Returns -1 for invalid buffers, -2 for allocation failure. */
int32_t pc_ingest(PCCloud *cloud, PCFrame frame);
PCStats pc_stats(const PCCloud *cloud);
size_t pc_copy_preview(const PCCloud *cloud, PCPoint *output, size_t capacity);
/* 0 = binary little-endian PLY, 1 = ASCII PLY, 2 = XYZ (three columns).
   All exports use right-handed Z-up coordinates: (x, -z, y), metres.
   Writes a temporary sibling and renames only after a successful close. */
int32_t pc_export(const PCCloud *cloud, const char *path, int32_t format,
                  char *error, size_t errorCapacity);

#ifdef __cplusplus
}
#endif
