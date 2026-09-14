# LiDAR Scanner for iPhone and iPad

An open-source LiDAR point-cloud scanner and exporter for LiDAR-equipped iPhone and iPad devices.

The app uses Apple ARKit scene depth to capture 3D points directly on supported devices and exports scans as standard point-cloud data. Its capture pipeline is deliberately designed **without an arbitrary total point-count limit**: points are streamed to disk in batches rather than accumulated indefinitely in memory.

> **Project status:** early development / experimental. The current implementation is intended as a transparent, inspectable foundation for field testing and further development.

## Core features

- LiDAR capture through ARKit `sceneDepth` / `smoothedSceneDepth`
- Live camera/AR preview
- RGB-coloured 3D points sampled from the camera image
- Confidence filtering of depth measurements
- Three capture-density presets
- Streaming point storage instead of a fixed in-memory point ceiling
- Binary little-endian PLY export (`x`, `y`, `z`, `red`, `green`, `blue`)
- Native iPhone and iPad support
- No external runtime dependencies

## Requirements

- Xcode 16 or later recommended
- iOS / iPadOS 17.0 or later
- A LiDAR-equipped iPhone or iPad
- Physical device required for LiDAR capture

The project configuration is stored in [`project.yml`](project.yml) and can be generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

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

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the acquisition and export pipeline.

## Roadmap

- On-device scan library and metadata
- XYZ / CSV export
- Optional confidence value in exported data
- Voxel-grid decimation and duplicate suppression
- Scan resume / recovery after interruptions
- Optional georeferencing / GNSS metadata
- Improved thermal and storage monitoring
- Larger-scene field validation

## Scientific and field use

The project is designed with transparent data acquisition in mind. For scientific use, device model, OS version, capture density, acquisition conditions, and subsequent processing should be documented together with the exported point cloud.

## AI-assisted development disclosure

This project was developed through an AI-assisted coding workflow using **ChatGPT by OpenAI**, under human direction and review by Dominik Hagmann. In informal terms, substantial parts of the initial codebase, project structure, and documentation were "vibe-coded" with ChatGPT. The resulting implementation was subsequently reviewed, tested, and validated by Dominik Hagmann during development.

The exact ChatGPT model used during every stage of the initial development was not recorded reliably; the repository therefore does not attribute the code to a specific model where that cannot be verified. See [`AI_DISCLOSURE.md`](AI_DISCLOSURE.md) for details.

## Citation

Citation metadata are provided in [`CITATION.cff`](CITATION.cff). Versioned releases can later be archived through Zenodo to obtain a DOI.

## License

MIT License. See [`LICENSE`](LICENSE).
