# Third-party components

The installed app performs capture, Gaussian optimization, rendering and report generation locally. Network access in `scripts/setup.sh` is for developer build dependencies only.

| Component | Pinned source | Role | License |
| --- | --- | --- | --- |
| msplat-ios | `frs0n/msplat-ios` at `e8611098583059b82e0b7d35259fb4e9c42df248` | Metal Gaussian optimization; derived from rayanht/msplat | Apache-2.0 |
| MetalSplatter | `scier/MetalSplatter` at `464eb37c55d90d7362a79120fdf8b50d4ae03296` | Native Gaussian rendering and PLY reading | MIT |
| nlohmann/json | 3.11.3, fetched by msplat CMake | Training-dataset parsing | MIT |
| nanoflann | 1.5.5, fetched by msplat CMake | Seed-neighbour lookup | BSD |
| spz-swift | 2.1.0 (`e2410c91bceba2539c11157ad92e488ef6e16416`), locked in Package.resolved | Splat file I/O | Apache-2.0 |

License texts are included in `LiDARScanner/ThirdPartyLicenses.txt` and shipped with the app. The upstream sources remain in `Dependencies/msplat` after setup for inspection.

`scripts/patch-engine.py` applies the following integration changes to the pinned msplat source:

- Compile shaders with Metal 3.1 for the iOS 18 deployment target.
- Turn stream read/write failures into exceptions, caught by the app's native bridge.
- Expose the selected camera index and effective image dimensions in each step's statistics, so the app can record exactly which image was used.

The optimizer, loss function and reconstruction algorithm are unchanged. The app records the source revision and patch identifier in every Gaussian scan. The app bridge catches C++ errors before returning to Swift, validates shader availability, and verifies the generated PLY size before publishing it.
