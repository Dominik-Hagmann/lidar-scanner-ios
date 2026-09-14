# LiDAR Scanner for iPhone and iPad

<p align="center">
  <img src="docs/app-icon.png" alt="LiDAR Scanner app icon" width="180">
</p>

An open-source LiDAR point-cloud scanner and exporter for LiDAR-equipped iPhone and iPad devices.

The app uses Apple ARKit scene depth to capture 3D points directly on supported devices and exports scans as standard point-cloud data. Its capture pipeline is deliberately designed to keep application-side processing simple and transparent: points are streamed to disk in batches rather than accumulated indefinitely in memory.

During scanning, points are serialized in compact 15-byte records and appended to a temporary point stream on disk. RAM usage therefore does not grow linearly with the total scan size. In practice, scan size is constrained by device storage, I/O throughput, thermal state, battery, and the selected density setting. The app reports the live point count and approximate raw data size so the operator can decide when a scan has become sufficiently large.

## Purpose

Numerous iPhone and iPad applications already support LiDAR scanning, photogrammetry, meshing, texturing, or complete 3D-model workflows, and many use paid or subscription-based export features. Direct export of a simple point cloud, however, is not always the central workflow. **LiDAR Scanner deliberately does less.**

The aim is to provide a straightforward way to acquire and export a minimally application-processed XYZ+RGB point cloud that can subsequently be inspected, cleaned, registered, analysed, or otherwise processed in dedicated software such as <a href="https://www.cloudcompare.org/" target="_blank" rel="noopener noreferrer">CloudCompare ↗</a>. Depending on file and 3D-data support, exported point clouds can also be uploaded to multimodal AI/LLM environments for rapid exploratory assessment, interpretation, generation of derived views or visualisations, and assistance with subsequent processing steps. Such AI-assisted workflows are intended as a complement rather than a substitute for geometric processing and metric verification in specialist software. The app does not perform mesh reconstruction, hole filling, voxel filtering, or other geometric post-processing before export. ARKit depth data are nevertheless already processed and sensor-fused by the Apple platform, so the exported data should not be interpreted as unprocessed raw sensor measurements.

The app was conceived primarily from the perspective of **archaeological fieldwork**, where rapid 3D recording can complement conventional documentation of excavation features, stratigraphic situations, architectural remains, sections, and other built or excavated structures. The same deliberately simple workflow can also be useful in other field sciences, for example for geological outcrops, geomorphological observations, forestry, cave documentation, or comparable small- to medium-scale recording tasks. Beyond research, it can also support rapid documentation in architecture, construction, real-estate and property documentation, facility management, and related professional contexts where a quickly acquired 3D record of spaces, structures, or existing conditions is useful.

It is intended as a lightweight rapid-documentation tool, not as a replacement for terrestrial laser scanning, survey-grade photogrammetry, or other techniques where higher metric accuracy, longer range, controlled georeferencing, or formal survey standards are required.

## Core features

- LiDAR capture through ARKit `sceneDepth` / `smoothedSceneDepth`
- Live camera/AR preview
- RGB-coloured 3D points sampled from the camera image
- Confidence filtering of depth measurements
- Three capture-density presets
- Streaming point storage
- Binary little-endian PLY export (`x`, `y`, `z`, `red`, `green`, `blue`)
- Native iPhone and iPad support
- No external runtime dependencies

## Requirements

- Xcode 16 or later recommended
- iOS / iPadOS 17.0 or later
- A LiDAR-equipped iPhone or iPad

The project configuration is stored in [`project.yml`](project.yml) and can be generated with <a href="https://github.com/yonaskolb/XcodeGen" target="_blank" rel="noopener noreferrer">XcodeGen ↗</a>.

```bash
brew install xcodegen
xcodegen generate
open LiDARScanner.xcodeproj
```

Alternatively, run:

```bash
bash scripts/bootstrap.sh
```

## Using the app

1. Build and run `LiDARScanner` on a LiDAR-equipped iPhone or iPad.
2. Grant camera access.
3. Select the desired capture density.
4. Tap **Start Scan** and move steadily through the scene.
5. Tap **Stop Scan**.
6. Tap **Export PLY** and use the system share sheet to save or transfer the point cloud.

## Capture densities

| Preset | Approx. frame interval | Depth stride | Intended use |
|---|---:|---:|---|
| Low | 0.20 s | 3 | Rapid documentation / large scenes |
| Standard | 0.15 s | 2 | General-purpose acquisition |
| High | 0.12 s | 1 | Dense capture of smaller scenes |

These values regulate sampling density, not the total point count.

## Output format

PLY files are written as `binary_little_endian 1.0` with the following vertex properties:

```text
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
```

Coordinates are stored in the ARKit world coordinate system in metres.

## Roadmap

The scope is intentionally narrow. Two small additions are currently envisaged:

- XYZ / CSV export
- GNSS metadata accompanying scans

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the acquisition and export pipeline.

## Scientific and field use

The implementation has been reviewed, tested, and validated during development. As with any mobile LiDAR workflow, achievable quality depends on device generation, acquisition distance, surface properties, lighting and tracking conditions, operator movement, and the scale and geometry of the recorded scene. For scientific use, the device model, OS version, capture density, acquisition conditions, and subsequent processing should therefore be documented together with the exported point cloud.

## How to cite

If you use **LiDAR Scanner for iPhone and iPad** in research, teaching, or published documentation, please cite the software. GitHub reads the repository's [`CITATION.cff`](CITATION.cff) file and provides a **“Cite this repository”** option on the repository page.

Suggested citation for the current version:

> Hagmann, D. (2026). *LiDAR Scanner for iPhone and iPad* (Version 0.1.0) [Computer software]. GitHub. <a href="https://github.com/Dominik-Hagmann/lidar-scanner-ios" target="_blank" rel="noopener noreferrer">https://github.com/Dominik-Hagmann/lidar-scanner-ios ↗</a>

For reproducible scientific work, please cite the specific version or release used. A DOI can be added through Zenodo when a versioned release is archived.

## Selected literature on iPhone/iPad LiDAR

The following publications provide context for the use, accuracy, limitations, and field applications of LiDAR integrated into Apple mobile devices:

- Antón, D., Mayoral-Valsera, J., Simón-Vallejo, M. D., Parrilla-Giráldez, R., & Cortés-Sánchez, M. (2025). Built-in smartphone LiDAR for archaeological and speleological research. *Journal of Archaeological Science, 181*, 106330. <a href="https://doi.org/10.1016/j.jas.2025.106330" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Bhatta, B. P., Shah, A., Chaulagain, M. K., Dhungana, A., Mandal, L., Koirala, P., Thapa, S., & Panday, U. S. (2025). Comparative Assessment of Archaeological Scene Reconstruction Using iPhone LiDAR Scanner. *Journal on Geoinformatics, Nepal, 24*, 9–19. <a href="https://doi.org/10.3126/njg.v24i1.79342" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Costantino, D., Vozza, G., Pepe, M., & Alfio, V. S. (2022). Smartphone LiDAR Technologies for Surveying and Reality Modelling in Urban Scenarios: Evaluation Methods, Performance and Challenges. *Applied System Innovation, 5*(4), 63. <a href="https://doi.org/10.3390/asi5040063" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Dora, D., Lazaridis, G., Tokmakidis, P., Trimmis, K. P., Veni, G., Tokmakidis, K., & Vouvalidis, K. (2026). Low-cost smartphone LiDAR for 3D cave mapping: comparing mobile and terrestrial laser scanning methods. *Geology Today, 42*, 147–153. <a href="https://doi.org/10.1111/gto.70022" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Furlan, L. M., & Piazentim, E. G. (2025). Smartphone-based LiDAR for generating Digital Outcrop Models (DOMs) with field validation. *Discover Geoscience, 3*, 137. <a href="https://doi.org/10.1007/s44288-025-00253-z" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Gollob, C., Ritter, T., Kraßnitzer, R., Tockner, A., & Nothdurft, A. (2021). Measurement of Forest Inventory Parameters with Apple iPad Pro and Integrated LiDAR Technology. *Remote Sensing, 13*(16), 3129. <a href="https://doi.org/10.3390/rs13163129" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Luetzenburg, G., Kroon, A., & Bjørk, A. A. (2021). Evaluation of the Apple iPhone 12 Pro LiDAR for an Application in Geosciences. *Scientific Reports, 11*, 22221. <a href="https://doi.org/10.1038/s41598-021-01763-9" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Luetzenburg, G., Kroon, A., Kjeldsen, K. K., Splinter, K. D., & Bjørk, A. A. (2024). High-resolution topographic surveying and change detection with the iPhone LiDAR. *Nature Protocols, 19*, 3520–3541. <a href="https://doi.org/10.1038/s41596-024-01024-9" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Paukkonen, N. (2023). Towards a Mobile 3D Documentation Solution. Video-Based Photogrammetry and iPhone 12 Pro as Fieldwork Documentation Tools. *Journal of Computer Applications in Archaeology, 6*(1), 143–154. <a href="https://doi.org/10.5334/jcaa.135" target="_blank" rel="noopener noreferrer">DOI ↗</a>
- Soyluoğlu, M., Orabi, R., Hermon, S., & Bakirtzis, N. (2025). Digitizing Challenging Heritage Sites with the Use of iPhone LiDAR and Photogrammetry: The Case-Study of Sourp Magar Monastery in Cyprus. *Geomatics, 5*(3), 44. <a href="https://doi.org/10.3390/geomatics5030044" target="_blank" rel="noopener noreferrer">DOI ↗</a>

## License

MIT License. See [`LICENSE`](LICENSE).

## AI-assisted development disclosure

This project was developed through an AI-assisted, informally **“vibe-coded”** workflow using **ChatGPT powered by GPT-6 Astra (OpenAI)**, under the direction, review, testing, and validation of the author. GPT-6 Astra contributed to the generation and revision of source code, project structure, configuration files, and documentation. See [`AI_DISCLOSURE.md`](AI_DISCLOSURE.md) for further details.
