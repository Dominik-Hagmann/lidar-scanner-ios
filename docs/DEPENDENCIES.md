# Tools and dependencies

[Back to the README](../README.md) · [Installation](INSTALLATION.md)

## What you install once

| Tool | Purpose | Preparation |
| --- | --- | --- |
| Xcode 16.4+ | Apple SDKs, Swift/C++ compilation, Metal shaders and signing | Install full Xcode, complete first launch and use a version supporting the connected device |
| Git and Git LFS | Fetch pinned source; process LFS pointers while skipping large example datasets | Git must be on `PATH`; `brew install git-lfs` |
| CMake 3.21+ | Configure and build the native Gaussian engine | `brew install cmake` |
| Python 3.9+ | Integration patching, cache verification and export checks | Must be on `PATH`; `brew install python` if needed |
| XcodeGen, optional | Regenerate `.xcodeproj` from `project.yml` | `brew install xcodegen` when using `--regenerate-project` |

Run `bash scripts/setup.sh --check` to check the normal setup prerequisites. The tools are not installed automatically. XcodeGen is checked when project generation is requested or the project file is missing.

## What setup and Xcode download

These are the pinned versions in this source revision, not claims about the latest upstream releases. Normal setup requires no manual library downloads.

| Component | Source / version | Used for | Resolved by |
| --- | --- | --- | --- |
| msplat-ios | [frs0n/msplat-ios](https://github.com/frs0n/msplat-ios), `e8611098583059b82e0b7d35259fb4e9c42df248` | Native Gaussian optimization | `scripts/prepare-gaussians.py` |
| MetalSplatter, including SplatIO | [scier/MetalSplatter](https://github.com/scier/MetalSplatter), `464eb37c55d90d7362a79120fdf8b50d4ae03296` | Gaussian rendering and file I/O | Xcode / Swift Package Manager |
| spz-swift | [scier/spz-swift](https://github.com/scier/spz-swift), 2.1.0 | Dependency in the Swift package graph | `Package.resolved` |
| swift-argument-parser | [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser), 1.8.2 | Dependency in the resolved Swift package graph | `Package.resolved` |
| nlohmann/json | [nlohmann/json](https://github.com/nlohmann/json), 3.11.3 | Native dataset parsing | Pinned engine’s `CMakeLists.txt` |
| nanoflann | [jlblancoc/nanoflann](https://github.com/jlblancoc/nanoflann), 1.5.5 | Native neighbour lookup | Pinned engine’s `CMakeLists.txt` |
| CLI11 | [CLIUtils/CLI11](https://github.com/CLIUtils/CLI11), 2.4.2 | Upstream CLI dependency fetched during CMake configuration | Pinned engine’s `CMakeLists.txt` |

A fetched or resolved package is not necessarily linked into the iOS app; the upstream project also defines development and command-line targets. Apple frameworks, including Metal, MetalKit, MetalPerformanceShaders, ImageIO and CoreGraphics, come from the Xcode SDKs.

The package sources and revisions are defined in [`project.yml`](../project.yml), the committed [`Package.resolved`](../LiDARScanner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved), and [`prepare-gaussians.py`](../scripts/prepare-gaussians.py). After setup, the native source and its CMake dependency declarations remain under `Dependencies/msplat`. See [third-party notices](../THIRD_PARTY_NOTICES.md) for shipped components and integration patches.

## Build outputs, cache and preservation

The app project uses `Dependencies/msplat/MsplatCore.xcframework` and two shader libraries, `default-ios.metallib` and `default-iossimulator.metallib`. Setup verifies both iPhone and Simulator native slices and checks that the shader files exist and are nonempty. It records SHA-256 hashes of the outputs and tracked, patched source files.

Cache reuse also requires the same source revision, integration/preparation scripts, selected Xcode, SDK versions, CMake version and deployment-target settings. A missing or changed required output forces a fresh build. The original `.scanner-build-5` stamp alone is insufficient and is no longer used.

New builds run in `Dependencies/.msplat-build-*`. A failed attempt does not replace the existing dependency tree. After a successful verified build, any old tree is retained under `Dependencies/preserved/`, including local edits; the active tree is the clean pinned source plus the repository’s integration patches. Local engine edits are preserved but are not merged into the replacement. App source, scan files and phone data are outside this operation.

## Developer checks

Setup regression tests use temporary fixture repositories and stubbed Apple build tools; they need Python and Git and do not download or build the real engine:

```sh
python3 Tests/test_setup.py
```

Run the existing geometry and export checks with:

```sh
bash Tests/run.sh
```

After successful setup, validate native app integration with:

```sh
xcodebuild -project LiDARScanner.xcodeproj -scheme LiDARScanner \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
bash scripts/test-ios.sh
```

The setup tests do not validate actual shader compilation or device capture. Record real builds and hardware checks separately in the [validation record](VALIDATION.md).
