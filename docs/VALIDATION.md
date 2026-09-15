# Validation Status

Test environment: macOS 26.6.2 on ARM64 with Xcode 26.6 (build 17F113), Apple Clang 21.0.0, and Python 3.9.6 on 15 September 2026. No physical LiDAR-capable device was included in this validation.

## Tests Performed

### Core and Export Tests

The C++ core used by the application was compiled and executed with AddressSanitizer and UndefinedBehaviorSanitizer checks enabled:

```sh
bash Tests/run.sh
```

Result: **passed**. The tests cover:

- back-projection, including viewing direction and the Y-axis sign, using known coordinates;
- a column-major 4 × 4 camera matrix with combined rotation and translation;
- scaled focal lengths and a two-dimensional sampling stride;
- depth, confidence, and colour images with deliberately padded rows;
- NaN, infinity, zero depth, depth values above the selected range, and invalid confidence values;
- duplicate observations, capped point counts, and negative voxel coordinates;
- replacement by higher-confidence observations and retention when encountering lower-confidence observations;
- full-range and limited-range YCbCr, BT.601/709, and the colour-sampling position;
- preview selection and resetting of the point set;
- export failures caused by a missing destination directory, an unknown format, or an empty point set;
- an independent Python parser for the PLY and XYZ files actually written by the application, covering field order, byte order, record length, point count, RGB values, confidence, and Z-axis orientation.

The tests additionally covered a complete synthetic point cloud containing **2,097,152 points in automatic mode** and a run with an explicit limit of **2,000,009 points**. They demonstrate the correct processing of larger automatically managed and explicitly capped point sets, the global consolidation of repeated observations, and complete PLY export. The generated files are independently checked for their headers, record counts, and first and last points.

### iOS Simulator Build

The following unsigned Debug build for the generic iOS Simulator was completed successfully under Xcode 26.6:

```sh
xcodebuild -project LiDARScanner.xcodeproj -scheme LiDARScanner \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

This provides evidence for Swift type checking, compilation of the C++ core, bridging-header integration, linking, resource processing, and application-bundle creation in the specified environment. The Simulator build does not test LiDAR capture, device signing, runtime behaviour, measurement quality, or performance limits on physical hardware.

## Tests Still Required on a Physical iPhone or iPad

The following tests have not yet been performed and passed:

1. Sign and install the application on a LiDAR-capable iPhone and iPad. Initially grant camera permission, then deny it once and re-enable it through Settings. On the iPad, additionally test portrait and landscape orientations, the controls, and the anchoring of the share sheet.
2. Capture a short scan of a matte, textured surface with known geometry. After panning the camera, points must appear in front of the camera and display the correct colours.
3. Capture a horizontal surface and known vertical and horizontal distances. Inspect the export in point-cloud software to confirm that the positive Z-axis points upwards, metres are used as the unit, and no mirroring is present. Document deviations from the control measurements; grid spacing does not constitute evidence of accuracy.
4. Export all three formats together with the JSON file using “Save to Files” and AirDrop, and open them on another device.
5. Test pausing, resuming, “New Scan”, the point limit, screen or camera interruption, transition to the background, and application restart. Completed saves must remain available in the archive. Following an interruption, capture into the same point set must not continue using a reinitialised camera pose.
6. Perform a longer recording on the target device and observe memory usage, device heating, frame rate, and errors when storage is nearly full. In automatic mode, specifically test the process-memory query and saving when the available-memory reserve falls below 256 MiB. This memory-monitoring behaviour has not been tested here because suitable Apple LiDAR hardware was unavailable. This version makes no performance or accuracy claim validated on physical hardware.

The successful core tests and Simulator build do not replace testing on physical LiDAR hardware. Version 1.0.0 must therefore be regarded as an implemented, partially validated project state.
