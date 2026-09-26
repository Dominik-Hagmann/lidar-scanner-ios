# Validation Status

## Current Status

The point-cloud app was successfully tested on a physical iPhone before the Gaussian extension. That result is retained and is not evidence for the new Gaussian mode. iPad device testing is not yet documented.

Version 1.2.0 (Build 4): the C++ core/export regression suite passes with AddressSanitizer and UndefinedBehaviorSanitizer (LeakSanitizer disabled in the Linux container). The initial native Simulator build and all nine scan-record/report tests passed in GitHub Actions run 55. The final revision also adds an unsigned iPhone Release build and a UI test for mode switching and the Gaussian archive. Physical Gaussian capture, Metal training quality, thermal behaviour and interactive rendering still require testing on a LiDAR-equipped iPhone with iOS 18+.

### Gaussian device check

- Capture a textured stationary subject, finish, and confirm that processing starts automatically without a network connection.
- Inspect the resulting scene by rotating and zooming; open its Gaussian PLY in another application.
- Pause processing, reopen the app and continue from a saved checkpoint. Check the report's completed and checkpoint step counts.
- Background the app during capture and during processing; confirm saved images remain available and recovery is reported accurately.
- Export the capture ZIP, processing log and narrative PDF. Check image counts, selected-camera records, coordinate convention, step counts and file hashes against the saved files.
- Return to Point Cloud mode and confirm that its capture, archive and PLY/XYZ export still work.

These are pending physical-device scenarios, not claimed test results.

## Automated Test Record

The following record describes the original core and Simulator validation of version 1.0.0 (Build 2). Current version and build identifiers are documented in the [README](../README.md), with subsequent changes listed in the [changelog](../CHANGELOG.md).

Test environment: macOS 26.6.2 on ARM64 with Xcode 26.6 (build 17F113), Apple Clang 21.0.0, and Python 3.9.6 on 15 September 2026.

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

## Device Validation Checklist

Use the following scenarios to document further device testing:

1. Sign and install the application on a LiDAR-capable iPhone and iPad. Initially grant camera permission, then deny it once and re-enable it through Settings. On the iPad, additionally test portrait and landscape orientations, the controls, and the anchoring of the share sheet.
2. Capture a short scan of a matte, textured surface with known geometry. After panning the camera, points must appear in front of the camera and display the correct colours.
3. Capture a horizontal surface and known vertical and horizontal distances. Inspect the export in point-cloud software to confirm that the positive Z-axis points upwards, metres are used as the unit, and no mirroring is present. Document deviations from the control measurements; grid spacing does not constitute evidence of accuracy.
4. Export all three formats together with the JSON file using “Save to Files” and AirDrop, and open them on another device.
5. Test pausing, resuming, “New Scan”, the point limit, screen or camera interruption, transition to the background, and application restart. Completed saves must remain available in the archive. Following an interruption, capture into the same point set must not continue using a reinitialised camera pose.
6. Perform a longer recording on the target device and observe memory usage, device heating, frame rate, and errors when storage is nearly full. In automatic mode, specifically test the process-memory query and saving when the available-memory reserve falls below 256 MiB.

Record the tested build, device model, operating-system version, and results for each scenario.
