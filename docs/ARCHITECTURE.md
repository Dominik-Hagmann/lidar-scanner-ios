# Architecture

## Acquisition pipeline

`ARViewContainer` provides the live RealityKit camera view and hands its `ARSession` to `LiDARScanner`.

`LiDARScanner` configures `ARWorldTrackingConfiguration` with `smoothedSceneDepth` when available and falls back to `sceneDepth`. AR frames are throttled according to the selected density preset and processed on a dedicated serial queue.

For each accepted depth pixel, the scanner:

1. reads metric depth from the ARKit depth map;
2. rejects invalid and low-confidence measurements;
3. maps the depth pixel into camera-image coordinates;
4. reconstructs the camera-space 3D coordinate using the camera intrinsics;
5. transforms the point into the ARKit world coordinate system;
6. samples YCbCr camera colour and converts it to RGB;
7. passes the point to `PointCloudWriter`.

## Streaming storage

`PointCloudWriter` does not retain the complete point cloud in RAM. It serializes each point as:

- X: Float32 little-endian – 4 bytes
- Y: Float32 little-endian – 4 bytes
- Z: Float32 little-endian – 4 bytes
- R: UInt8 – 1 byte
- G: UInt8 – 1 byte
- B: UInt8 – 1 byte

Total: **15 bytes per point**.

Points are appended to a `.pcbin` working file in batches. The total number of captured points is tracked separately.

## PLY export

The internal binary record layout intentionally matches the vertex body of a binary little-endian PLY file containing Float32 XYZ and UInt8 RGB. Export therefore consists of writing a PLY header with the final vertex count and streaming the `.pcbin` payload into the output file without materialising the entire scan in memory.

## Scaling characteristics

This design removes an artificial global point ceiling. Memory use is dominated by one AR frame plus one temporary processing batch rather than total scan size. Storage consumption is approximately:

- 1 million points: ~15 MB raw
- 10 million points: ~150 MB raw
- 50 million points: ~750 MB raw

PLY header overhead is negligible.

Large scans remain subject to mobile-device constraints such as storage capacity, write throughput, thermal throttling, and battery life.
