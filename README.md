# LiDAR Scanner for iPhone and iPad

<p align="center">
  <img src="docs/app-icon.png" alt="LiDAR Scanner app icon" width="140">
</p>

Capture coloured point clouds or create Gaussian scenes on a LiDAR-equipped iPhone or iPad. Processing runs locally on the device. The interface is available in English and German; no API keys, servers or in-app accounts are required.

| Mode | Use | Main outputs |
| --- | --- | --- |
| Point Cloud | Capture LiDAR depth points with camera-derived colours | PLY, XYZ and JSON metadata |
| Gaussian Splatting | Capture views and optimize a scene on the device | Gaussian PLY, capture ZIP and processing records |

Both modes provide an optional PDF report. See the [usage guide](docs/USAGE.md) for controls, storage and export details.

## Current status and requirements

**Version 1.2.0 · Build 4.** The previous point-cloud version was tested on a physical iPhone. The Gaussian extension has automated build and test coverage; physical Gaussian capture, processing quality and performance still require device validation. See the [validation record](docs/VALIDATION.md) and [changelog](CHANGELOG.md).

- **Device:** a LiDAR-equipped iPhone or iPad running iOS/iPadOS 18 or later. The Simulator cannot capture scans. iPhone uses portrait orientation; iPad supports portrait and landscape. iPad device testing is not yet documented.
- **Mac:** full Xcode 16.4 or later, with support for the OS installed on your device. Complete Xcode’s first launch and component installation.
- **Tools:** Git, Git LFS, CMake 3.21+ and Python 3.9+. XcodeGen is needed only to regenerate the project.
- **Connection:** internet access on the Mac for dependency downloads and Xcode signing. Scanning and processing on the phone work offline.

**Scientific use:** coordinates are local, with no geographic reference. Voxel spacing is a sampling setting, not a statement of measurement accuracy. Long scans may drift; validate measurements against control geometry. [Data conventions and limitations](docs/USAGE.md#export-formats).

## First installation

Install [Xcode](https://developer.apple.com/xcode/) and [Homebrew](https://brew.sh/) first. In Terminal:

```sh
brew install cmake git-lfs
git clone https://github.com/Dominik-Hagmann/lidar-scanner-ios.git
cd lidar-scanner-ios
bash scripts/setup.sh --open
```

Setup checks prerequisites, downloads and builds the pinned native Gaussian engine, resolves the locked Swift packages, and opens the included Xcode project. **You do not need to find or download the individual libraries yourself.** The first native build can take several minutes. [All dependencies and their sources](docs/DEPENDENCIES.md).

In Xcode, add your Apple Account under **Settings → Accounts**. Select **Target LiDARScanner → Signing & Capabilities**, choose your **Team**, and leave automatic signing enabled. Connect and unlock your iPhone, select it as the run destination, then press **⌘R**. Complete any device connection, Developer Mode and camera-access prompts.

For ZIP downloads, tool installation details and signing: [installation guide](docs/INSTALLATION.md).

## Update an existing installation

**Keep the existing app, Team and Bundle Identifier to retain access to its scan archive.** Back up scans and save local project changes before updating the source. Then run `bash scripts/setup.sh` in the updated checkout and deploy from Xcode to the same device. Default setup preserves the existing Xcode project; it does not regenerate personal signing settings.

Follow the [update guide](docs/INSTALLATION.md#update-an-existing-installation), including how to handle local changes and when project regeneration is appropriate.

## First scan

1. Choose **Point Cloud** or **Gaussian Splatting**.
2. Select **Start Scan** and move slowly around a stationary subject.
3. For a point cloud, select **Pause**, then **Export**. For Gaussian capture, select **Finish and Create**, keep the app open during processing, then **Share 3D Scene**.

Point clouds are saved in `Scans`; Gaussian captures in `GaussianScans`, under the app’s Documents folder. The archive buttons reopen saved items. The [usage guide](docs/USAGE.md) explains Files access, interruption recovery and both workflows.

## Troubleshooting

Check the Mac with `bash scripts/setup.sh --check`; this does not download dependencies or change the project. If a native download or build is interrupted, fix the reported cause and rerun setup. Existing dependency files are preserved before a verified replacement is installed.

<a id="troubleshooting-app-no-longer-available"></a>
**“App no longer available” / „App ist nicht mehr verfügbar“:** follow the [recovery steps](docs/TROUBLESHOOTING.md#app-no-longer-available). Keep the installed app and its data.

[Missing tools, interrupted downloads and stale builds](docs/TROUBLESHOOTING.md).

## Documentation

| Topic | Guide |
| --- | --- |
| Installation, signing and updates | [Installation](docs/INSTALLATION.md) |
| Tools, packages, exact revisions and build checks | [Dependencies](docs/DEPENDENCIES.md) |
| Capturing, exporting, storage and limitations | [Usage](docs/USAGE.md) |
| Geometry, architecture and data provenance | [Technical description](docs/TECHNICAL_DESCRIPTION.md) |
| Completed tests and pending device validation | [Validation](docs/VALIDATION.md) |
| Research context | [Selected literature](docs/REFERENCES.md) |
| Contributing code | [Contributing](CONTRIBUTING.md) |

## Roadmap

CSV export and GNSS metadata are planned; neither is a feature of version 1.2.0 (Build 4).

## Citation and licence

Cite the version and build used: Hagmann, D. (2026). *LiDAR Scanner for iPhone and iPad* (Version 1.2.0, Build 4) [Computer software]. See [CITATION.cff](CITATION.cff).

The app source is available under the [MIT License](LICENSE). Dependencies have their own [third-party notices](THIRD_PARTY_NOTICES.md). [AI-assisted development provenance](AI_DISCLOSURE.md) is documented separately.
