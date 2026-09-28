# Using LiDAR Scanner

[Back to the README](../README.md) · [Installation and updates](INSTALLATION.md)

## Gaussian Splatting

1. Select **Gaussian Splatting**, then **Start Scan**.
2. Move slowly around the subject, keeping it in view. The app selects and saves distinct views automatically.
3. Tap **Finish and Create**. Processing starts on the iPhone; the screen shows the actual completed steps. Keep the app open.
4. View the scene, then use **Share 3D Scene**. **Export Capture** provides the images, camera calibration and poses for other software.

**Details** explains the current state. **Export Report** creates an optional narrative PDF, and **Export Processing Log** provides exact recorded settings, frame decisions, processing steps and file hashes. Reports are also available for saved point clouds; they state the limits of the metadata recorded by that mode.

Captures are saved progressively under `GaussianScans`. Processing checkpoints are saved every 100 steps and when a pause can be handled. After interruption, reopen the scan from the folder icon and choose **Continue Processing**. A sudden termination can lose work since the last durable save; recovery records this explicitly. Pausing does not delete the capture.

Gaussian PLY uses local **metres, Y up**. Point-cloud PLY/XYZ uses **metres, Z up**. Both coordinate conventions are included in their metadata. Gaussian optimization uses ARKit poses directly, without separate pose refinement. Appearance, speed, memory use and heat require validation on the target iPhone; the app does not assert survey accuracy or complete coverage.

## Capturing and Exporting a Point Cloud

1. Before capturing the first point, optionally use the sliders icon to configure **voxel-grid spacing, confidence threshold, depth range, and point limit**.
2. Wait until **“Tracking stable”** is displayed.
3. Select **“Start Scan”** and move the camera slowly across the scene. Points are superimposed on the camera image; the point icon shows or hides them.
4. Select **“Pause”**. The current state is saved automatically. The scan can be resumed provided that the camera session continues without interruption.
5. Use the cube icon to rotate and zoom the current point cloud. The preview displays no more than 40,000 points selected evenly from the point list; the export contains the complete stored point set.
6. Select **“Export”**, enter a designation, choose a format, and press **“Save and Share”**.
7. In the iOS share sheet, select **“Save to Files”**, AirDrop, or another destination. The point file and metadata are offered together.

Completed saves are stored under **Files → On My iPhone** or **On My iPad → LiDAR-Scanner → Scans**. The folder icon opens the internal archive. Previously generated file formats can be shared again, and individual saves can be deleted. Saving an unchanged scan again under the same designation reuses the existing save. Additional captured points or a different designation create a new archived state.

## Point Count and Memory Management

The default setting is **“Automatic · No Fixed Point Count”**. Before and after processing a depth image, the application checks the memory available to its process. If the available memory falls below a reserve of 256 MiB, capture is stopped and the application attempts to save the scan acquired up to that point. An operating-system memory warning also triggers a save attempt. The attainable point count depends on the device and its current memory conditions; saving before an abrupt process termination cannot be guaranteed.

Alternatively, fixed limits of **500,000, 1 million, 2 million, 5 million, or 10 million points** can be selected. Memory monitoring remains active when a fixed limit is used. Settings can be changed before starting a new scan. The preview continues to display a maximum of 40,000 points; all captured points are exported.

## Export Formats

| Format | Content | Encoding |
| --- | --- | --- |
| `points.ply` | X, Y, Z, red, green, blue, confidence | Binary little-endian; 16 bytes per point plus header |
| `points-ascii.ply` | Identical fields | Text PLY with a decimal point |
| `points.xyz` | X, Y, Z | Three space-separated columns without a header |
| `metadata.json` | Designation, times, settings, point count, depth-image dimensions, provenance, and coordinate transformation | UTF-8; ISO 8601 dates |

Every save contains a binary PLY file. Selecting ASCII PLY or XYZ additionally generates the chosen file. PLY colours are 8-bit RGB values. Confidence is stored as an additional `uchar` field using the ARKit categories 0, 1, and 2. Software that does not interpret this field can still read the coordinates and colours.

**Coordinates:** metres; local right-handed coordinate system; positive Z points upwards. The transformation from the ARKit world coordinate system is `(X, Y, Z) = (x, −z, y)`. The origin is established when the AR session starts or when it is reset by selecting **“New Scan”**. No geographic reference, EPSG identifier, or north orientation is assigned. The data can subsequently be registered using external control points; the application does not perform this step.

## Captured Data

The application uses `ARFrame.sceneDepth`, the corresponding confidence map, camera calibration, and camera pose. Colours are obtained from the same `ARFrame.capturedImage`. It accumulates depth points across multiple frames; these are neither mesh vertices nor ordinary AR tracking feature points.

`sceneDepth` is an Apple-processed depth map derived from LiDAR and camera data. The data are **not unprocessed individual laser measurements**. Apple’s presentation of the [Depth API](https://developer.apple.com/videos/play/wwdc2020/10611/) explains this data provenance. The application does not apply the additional temporal smoothing provided through `smoothedSceneDepth`.

The default voxel-grid spacing of 1 cm describes spatial subsampling. It is **not a claim of 1 cm accuracy**. One observation is initially retained per grid cell; a later observation replaces it only if it has higher confidence. No averaging, surface reconstruction, or subsequent global registration is performed.

## Limitations of This Build

- Capture requires LiDAR-equipped iPhone or iPad hardware running at least iOS or iPadOS 18. iPhone is supported in portrait orientation; iPad is supported in portrait and landscape orientations. iPad device testing is not yet documented.
- Default settings are 0.2–5 m axial depth, medium or high confidence, every second depth pixel along each image axis, 1 cm voxel-grid spacing, and automatic monitoring of available memory without a selected fixed point count. Optional point limits range from 500,000 to 10 million.
- No points are added while tracking is limited. Relocalisation, camera interruption, transition to the background, and memory warnings close the current capture. The accumulated point cloud remains exportable; subsequent capture begins as a new scan.
- Points already accumulated are not retrospectively optimised following later ARKit pose corrections. Long acquisitions may exhibit drift. Metrological validation must use control geometry on the actual device.
- The application saves automatically when capture is paused and makes a best-effort save when moved to the background. If the application is terminated before saving is complete, points captured since the most recent completed save may be lost. Continuous long-term logging is not guaranteed.
- Saved point files can be shared again. Restarting the application does not resume the previous AR session, and archived scans are not reloaded for continued acquisition.
- The application does not import data from other scanning applications and does not export LAS, LAZ, or E57 files or create meshes. The available open point formats provide a basis for subsequent conversion.
