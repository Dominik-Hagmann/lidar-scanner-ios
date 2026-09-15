# Technical Description

## Data Flow and Coordinate Systems

For each processed `ARFrame`, the application uses `sceneDepth.depthMap`, `sceneDepth.confidenceMap`, `capturedImage`, `camera.intrinsics`, `camera.imageResolution`, and `camera.transform`. The depth and colour images are read from the same frame. Each `CVPixelBuffer` is locked for access, and all row strides are obtained from the respective buffer. The confidence map must have the same dimensions as the depth map. The processing pipeline accepts Float32 depth values, UInt8 confidence values, and bi-planar 8-bit YCbCr camera images in either full-range or video-range format.

The intrinsic parameters are scaled independently along the X and Y axes from the camera-image resolution to the depth-image resolution. For a depth pixel `(u, v)` with axial depth `d`, the following equations apply in ARKit’s camera coordinate system:

```text
x_camera =  (u − cx_depth) × d / fx_depth
y_camera = −(v − cy_depth) × d / fy_depth
z_camera = −d
p_world  = camera.transform × [x_camera, y_camera, z_camera, 1]
```

The ARKit camera’s viewing direction lies along its negative Z-axis. Depth pixels use an image Y-axis directed downwards. Both sign corrections are therefore required. Depth is not interpreted as the Euclidean distance along a normalised viewing ray. The image grid remains in sensor coordinates; the interface orientation must not additionally be applied to this back-projection.

For export, the ARKit world coordinate system is mapped to `(x, −z, y)`. This rotation preserves right-handedness and aligns the positive Z-axis upwards. The 4 × 4 transformation matrix stored as a flat list in JSON uses row-major order. By contrast, the camera matrix supplied by ARKit is stored in column-major order in memory. A dedicated test verifies rotation and translation to detect any confusion between these conventions.

## Filtering and Representation

Non-finite depth values, values outside the selected range, and confidence values below the selected threshold are discarded. Invalid confidence categories outside the range 0–2 are likewise discarded. Depth pixels are sampled at a fixed stride along both image axes.

A voxel key consists of the three integer coordinates `floor(x/s)`, `floor(y/s)`, and `floor(z/s)`, where `s` is the voxel size in metres. The use of `floor` prevents values on opposite sides of zero from being erroneously merged when coordinates are negative. One point is stored for each occupied voxel. A later point replaces the representative only if it has a higher confidence level. The original point observation, together with its colour and confidence values, therefore remains a single unit.

`acceptedSamples` counts all valid observations assigned to a stored voxel, including repeated observations. `pointCount` counts the representatives that are actually stored. These values consequently describe different quantities. `activeSeconds` is a capture duration derived from the timestamps of processed frames; longer gaps are not included in full. It is not a high-precision time log.

## Colours

The depth-pixel position is mapped proportionally into the luma and chroma planes of the camera image. The core accounts for full-range or video-range values and applies BT.601 or BT.709 according to the image-buffer matrix attachment. If this attachment is absent or specifies another matrix, BT.601 is used. The result is visual RGB texturing; no radiometric calibration is performed.

## Resources and Concurrency

`ARSession` delegate callbacks occur on the main queue. A single-flight gate retains no more than one `ARFrame` for processing at any given time. A serial background queue has exclusive ownership of the point-cloud core, its metadata counters, and all file operations. This prevents concurrent modifications while a scan is being saved. At most approximately 6.7 frames are processed per second, and up to 40,000 preview points are generated no more than twice per second. The actual rate depends on the hardware and selected settings.

`settings.maxPoints = 0` activates automatic memory monitoring without a fixed point count. Values greater than zero impose an additional explicit point limit. The internal 32-bit point indexing theoretically limits the numerical range to 4,294,967,295 points; this is not a guaranteed scan capacity on actual devices.

Before and after processing each frame, the application checks the memory available to its process using `os_proc_available_memory()` from `os/proc.h`. If the available memory falls below the 256 MiB reserve, the application closes the capture session and attempts to save the scan. The same monitoring remains active when an explicit point limit has been selected. An operating-system memory warning provides an additional trigger. The reserve is a conservative implementation decision, not a threshold validated on physical hardware. It cannot rule out abrupt operating-system termination if memory demand increases suddenly. Apple describes this process-memory query in [Profile and optimize your game’s memory](https://developer.apple.com/videos/play/wwdc2022/10106/).

Points are stored in a segmented `std::deque`; when the collection grows, a complete contiguous point buffer does not have to be doubled and copied. The global voxel index is partitioned across 64 hash tables. Each voxel coordinate is assigned deterministically to one table, ensuring that duplicate detection applies across the entire scan. This partitioning reduces the size of individual temporary bucket allocations during growth. Starting a new scan clears the point collection and releases additional container capacity on a best-effort basis. Export continues to traverse the complete collection sequentially.

The processing pipeline does not retrospectively adjust stored points in response to pose corrections and does not perform loop-closure optimisation. While the session is `.relocalizing`, no further points are therefore written to the same collection. An ordinary pause leaves the `ARSession` active; moving the application to the background or interrupting the camera prevents the same scan from subsequently being continued.

## File Integrity and Archive

The C++ exporter initially writes to a temporary `.partial` file, verifies the stream state and successful closure, and only then renames the file. Each binary PLY record consists of exactly three little-endian Float32 values and four UInt8 values. No C structure, including compiler-dependent padding bytes, is written directly to the file. Text formats use the classic locale and nine significant digits for Float32 values.

New archived saves are assembled in a hidden staging directory. After the point file and JSON metadata have been written successfully, the entire directory is moved to its visible name. The archive displays only complete saves containing metadata and a binary PLY file. If an error is caught, the staging directory is removed; following abrupt process termination, a hidden residual directory may remain. Existing complete saves are not overwritten by such residual data. No guaranteed protection is provided against abrupt operating-system termination or power loss during saving.

## Apple Interfaces Used

- [Explore ARKit 4 – Depth API and point clouds](https://developer.apple.com/videos/play/wwdc2020/10611/)
- [Displaying a point cloud using scene depth](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth)
- [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata)
- [ARFrame.sceneDepth](https://developer.apple.com/documentation/arkit/arframe/scenedepth)
- [ARCamera.intrinsics](https://developer.apple.com/documentation/arkit/arcamera/intrinsics)

The project code was developed independently; no Apple sample code was incorporated into the package.
