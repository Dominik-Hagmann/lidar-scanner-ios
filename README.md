# LiDAR Scanner for iPhone and iPad

<p align="center">
  <img src="docs/app-icon.png" alt="LiDAR Scanner app icon" width="180">
</p>

**LiDAR Scanner** is a native, open-source application for capturing scenes with LiDAR-equipped iPhones and iPads and exporting coloured point clouds. iPhone is supported in portrait orientation; iPad is supported in portrait and landscape orientations. Controls use a limited width on larger displays.

**Interface language:** Build 2 currently has a German-language user interface. The instructions below reproduce the current German interface labels and provide English translations where useful.

The application is designed as a transparent tool for producing an XYZ+RGB point cloud with minimal additional application-level processing. It neither generates a mesh nor performs photogrammetric reconstruction, and it does not replace survey-controlled acquisition. Its principal purpose is rapid documentation in archaeology and other field sciences, followed by analysis in specialised point-cloud software.

**Project status:** The app bundle identifies the project state provided here as Build 2. The C++17 core and export tests have passed, and an unsigned iOS Simulator build has completed successfully. Capture on a physical LiDAR-equipped iPhone or iPad has not yet been tested. The repository contains source code; it does not contain a signed IPA file, an App Store distribution, or a tagged public release.

## Installation on an iPhone or iPad

Installation requires a **LiDAR-equipped iPhone or iPad**, **iOS or iPadOS 17 or later**, and a **Mac with a version of Xcode that supports the operating system installed on the connected device**. The application checks LiDAR support at runtime. The Simulator and devices without a LiDAR sensor cannot capture a scene.

1. Clone the repository, or download and extract the source code as a ZIP archive.
2. Open `LiDARScanner.xcodeproj` in Xcode.
3. Add your Apple Account under **Xcode → Settings → Accounts**.
4. Under **Target LiDARScanner → Signing & Capabilities**, select your own **Team** and leave **Automatically manage signing** enabled. If the bundle identifier is already in use, replace `at.lidarscanner.scanner` with your own unique identifier.
5. Connect the iPhone or iPad to the Mac, confirm the connection on the device, and select it as the destination in Xcode. Enable **Developer Mode** on the device if requested by Xcode.
6. Select **Run** or press **⌘R**. Grant camera access when the application is launched for the first time.

The checked-in Xcode project can be opened directly. Its reproducible configuration is also stored in [`project.yml`](project.yml). Following structural project changes, it can be regenerated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) by running `xcodegen generate` or `bash scripts/bootstrap.sh`.

Apple documents device installation in [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) and [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device). Interface labels may differ slightly depending on the language configured in Xcode.

No external Swift packages, API keys, servers, or in-app accounts are required. Processing takes place on the device. The share sheet passes only the selected export files to the destination chosen by the user.

## Capturing and Exporting a Scan

1. Before capturing the first point, optionally use the sliders icon to configure **voxel-grid spacing, confidence threshold, depth range, and point limit**.
2. Wait until **“Tracking stabil”** (“Tracking stable”) is displayed.
3. Select **“Scan starten”** (“Start scan”) and move the camera slowly across the scene. Points are superimposed on the camera image; the point icon shows or hides them.
4. Select **“Pausieren”** (“Pause”). The current state is saved automatically. The scan can be resumed provided that the camera session continues without interruption.
5. Use the cube icon to rotate and zoom the current point cloud. The preview displays no more than 40,000 points selected evenly from the point list; the export contains the complete stored point set.
6. Select **“Exportieren”** (“Export”), enter a designation, choose a format, and press **“Sichern und teilen”** (“Save and share”).
7. In the iOS share sheet, select **“In Dateien sichern”** (“Save to Files”), AirDrop, or another destination. The point file and metadata are offered together.

Completed saves are stored under **Files → On My iPhone** or **On My iPad → LiDAR-Scanner → Scans**. The folder icon opens the internal archive. Previously generated file formats can be shared again, and individual saves can be deleted. Saving an unchanged scan again under the same designation reuses the existing save. Additional captured points or a different designation create a new archived state.

## Point Count and Memory Management

The default setting is **“Automatisch · keine feste Punktzahl”** (“Automatic · no fixed point count”). Before and after processing a depth image, the application checks the memory available to its process. If the available memory falls below a reserve of 256 MiB, capture is stopped and the application attempts to save the scan acquired up to that point. An operating-system memory warning also triggers a save attempt. The attainable point count depends on the device and its current memory conditions; saving before an abrupt process termination cannot be guaranteed.

Alternatively, fixed limits of **500,000, 1 million, 2 million, 5 million, or 10 million points** can be selected. Memory monitoring remains active when a fixed limit is used. Settings can be changed before starting a new scan. The preview continues to display a maximum of 40,000 points; all captured points are exported.

## Export Formats

| Format | Content | Encoding |
| --- | --- | --- |
| `points.ply` | X, Y, Z, red, green, blue, confidence | Binary little-endian; 16 bytes per point plus header |
| `points-ascii.ply` | Identical fields | Text PLY with a decimal point |
| `points.xyz` | X, Y, Z | Three space-separated columns without a header |
| `metadata.json` | Designation, times, settings, point count, depth-image dimensions, provenance, and coordinate transformation | UTF-8; ISO 8601 dates |

Every save contains a binary PLY file. Selecting ASCII PLY or XYZ additionally generates the chosen file. PLY colours are 8-bit RGB values. Confidence is stored as an additional `uchar` field using the ARKit categories 0, 1, and 2. Software that does not interpret this field can still read the coordinates and colours.

**Coordinates:** metres; local right-handed coordinate system; positive Z points upwards. The transformation from the ARKit world coordinate system is `(X, Y, Z) = (x, −z, y)`. The origin is established when the AR session starts or when it is reset by selecting **“Neuer Scan”** (“New scan”). No geographic reference, EPSG identifier, or north orientation is assigned. The data can subsequently be registered using external control points; the application does not perform this step.

## Captured Data

The application uses `ARFrame.sceneDepth`, the corresponding confidence map, camera calibration, and camera pose. Colours are obtained from the same `ARFrame.capturedImage`. It accumulates depth points across multiple frames; these are neither mesh vertices nor ordinary AR tracking feature points.

`sceneDepth` is an Apple-processed depth map derived from LiDAR and camera data. The data are **not unprocessed individual laser measurements**. Apple’s presentation of the [Depth API](https://developer.apple.com/videos/play/wwdc2020/10611/) explains this data provenance. The application does not apply the additional temporal smoothing provided through `smoothedSceneDepth`.

The default voxel-grid spacing of 1 cm describes spatial subsampling. It is **not a claim of 1 cm accuracy**. One observation is initially retained per grid cell; a later observation replaces it only if it has higher confidence. No averaging, surface reconstruction, or subsequent global registration is performed.

## Limitations of This Build

- Capture requires LiDAR-equipped iPhone or iPad hardware running at least iOS or iPadOS 17. iPhone is supported in portrait orientation; iPad is supported in portrait and landscape orientations. The iPad target family and orientation entries are enabled in the Xcode project, but hardware testing remains outstanding.
- Default settings are 0.2–5 m axial depth, medium or high confidence, every second depth pixel along each image axis, 1 cm voxel-grid spacing, and automatic monitoring of available memory without a selected fixed point count. Optional point limits range from 500,000 to 10 million.
- No points are added while tracking is limited. Relocalisation, camera interruption, transition to the background, and memory warnings close the current capture. The accumulated point cloud remains exportable; subsequent capture begins as a new scan.
- Points already accumulated are not retrospectively optimised following later ARKit pose corrections. Long acquisitions may exhibit drift. Metrological validation must use control geometry on the actual device.
- The application saves automatically when capture is paused and makes a best-effort save when moved to the background. If the application is terminated before saving is complete, points captured since the most recent completed save may be lost. Continuous long-term logging is not guaranteed.
- Saved point files can be shared again. Restarting the application does not resume the previous AR session, and archived scans are not reloaded for continued acquisition.
- The application does not import data from other scanning applications and does not export LAS, LAZ, or E57 files or create meshes. The available open point formats provide a basis for subsequent conversion.

## Roadmap

The following additions are prospective and are not features of Build 2:

1. Complete German and English localisation of the application interface and all user-facing messages.
2. CSV export as an additional open text format.
3. GNSS metadata accompanying scans.

## Architecture and Validation

`LiDARScanner/ScanModel.swift` controls the session, permissions, interruptions, and saving. `DepthProcessor.swift` passes buffered depth and colour data to `Core/PointCloudCore.cpp`. The core performs back-projection, voxel selection, and file export. `Views/` contains the native interface and the camera and point previews. An Objective-C bridging header connects the C interface to Swift.

The tests require a C++17 compiler and Python 3:

```sh
bash Tests/run.sh
```

To build the application on a Mac with Xcode:

```sh
xcodebuild -project LiDARScanner.xcodeproj -scheme LiDARScanner \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

A Simulator build tests the iOS integration; LiDAR functionality can be tested only on a physical device. The GitHub Actions workflow reproducibly generates the project from [`project.yml`](project.yml) before running the Simulator build. Details of the geometry and current validation status are provided in [`docs/TECHNICAL_DESCRIPTION.md`](docs/TECHNICAL_DESCRIPTION.md) and [`docs/VALIDATION.md`](docs/VALIDATION.md).

## Citation

Scientific, educational, or documentary use should cite the specific software build used. GitHub reads [`CITATION.cff`](CITATION.cff) and provides a “Cite this repository” option on the repository page.

> Hagmann, D. (2026). *LiDAR Scanner for iPhone and iPad* (Build 2) [Computer software]. GitHub. https://github.com/Dominik-Hagmann/lidar-scanner-ios

## Selected Literature on LiDAR for iPhone and iPad

- Antón, D., Mayoral-Valsera, J., Simón-Vallejo, M. D., Parrilla-Giráldez, R., & Cortés-Sánchez, M. (2025). Built-in smartphone LiDAR for archaeological and speleological research. *Journal of Archaeological Science, 181*, 106330. [https://doi.org/10.1016/j.jas.2025.106330](https://doi.org/10.1016/j.jas.2025.106330)
- Bhatta, B. P., Shah, A., Chaulagain, M. K., Dhungana, A., Mandal, L., Koirala, P., Thapa, S., & Panday, U. S. (2025). Comparative Assessment of Archaeological Scene Reconstruction Using iPhone LiDAR Scanner. *Journal on Geoinformatics, Nepal, 24*, 9–19. [https://doi.org/10.3126/njg.v24i1.79342](https://doi.org/10.3126/njg.v24i1.79342)
- Costantino, D., Vozza, G., Pepe, M., & Alfio, V. S. (2022). Smartphone LiDAR Technologies for Surveying and Reality Modelling in Urban Scenarios: Evaluation Methods, Performance and Challenges. *Applied System Innovation, 5*(4), 63. [https://doi.org/10.3390/asi5040063](https://doi.org/10.3390/asi5040063)
- Dora, D., Lazaridis, G., Tokmakidis, P., Trimmis, K. P., Veni, G., Tokmakidis, K., & Vouvalidis, K. (2026). Low-cost smartphone LiDAR for 3D cave mapping: comparing mobile and terrestrial laser scanning methods. *Geology Today, 42*, 147–153. [https://doi.org/10.1111/gto.70022](https://doi.org/10.1111/gto.70022)
- Furlan, L. M., & Piazentim, E. G. (2025). Smartphone-based LiDAR for generating Digital Outcrop Models (DOMs) with field validation. *Discover Geoscience, 3*, 137. [https://doi.org/10.1007/s44288-025-00253-z](https://doi.org/10.1007/s44288-025-00253-z)
- Gollob, C., Ritter, T., Kraßnitzer, R., Tockner, A., & Nothdurft, A. (2021). Measurement of Forest Inventory Parameters with Apple iPad Pro and Integrated LiDAR Technology. *Remote Sensing, 13*(16), 3129. [https://doi.org/10.3390/rs13163129](https://doi.org/10.3390/rs13163129)
- Luetzenburg, G., Kroon, A., & Bjørk, A. A. (2021). Evaluation of the Apple iPhone 12 Pro LiDAR for an Application in Geosciences. *Scientific Reports, 11*, 22221. [https://doi.org/10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Luetzenburg, G., Kroon, A., Kjeldsen, K. K., Splinter, K. D., & Bjørk, A. A. (2024). High-resolution topographic surveying and change detection with the iPhone LiDAR. *Nature Protocols, 19*, 3520–3541. [https://doi.org/10.1038/s41596-024-01024-9](https://doi.org/10.1038/s41596-024-01024-9)
- Paukkonen, N. (2023). Towards a Mobile 3D Documentation Solution. Video-Based Photogrammetry and iPhone 12 Pro as Fieldwork Documentation Tools. *Journal of Computer Applications in Archaeology, 6*(1), 143–154. [https://doi.org/10.5334/jcaa.135](https://doi.org/10.5334/jcaa.135)
- Soyluoğlu, M., Orabi, R., Hermon, S., & Bakirtzis, N. (2025). Digitizing Challenging Heritage Sites with the Use of iPhone LiDAR and Photogrammetry: The Case-Study of Sourp Magar Monastery in Cyprus. *Geomatics, 5*(3), 44. [https://doi.org/10.3390/geomatics5030044](https://doi.org/10.3390/geomatics5030044)

## Licence and Development Provenance

The source code is available under the [MIT License](LICENSE). Information about AI-assisted development is provided in [`AI_DISCLOSURE.md`](AI_DISCLOSURE.md).
