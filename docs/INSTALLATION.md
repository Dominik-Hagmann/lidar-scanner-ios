# Installation and updates

[Back to the README](../README.md) · [Dependency inventory](DEPENDENCIES.md) · [Troubleshooting](TROUBLESHOOTING.md)

## Prepare the Mac

1. Install the full [Xcode application](https://developer.apple.com/xcode/) and complete its first launch, including required components. The project requires Xcode 16.4 or later; the selected Xcode must also support the OS on the connected device. Command Line Tools alone are insufficient.
2. Install [Homebrew](https://brew.sh/) if needed and follow the installer’s shell configuration instructions.
3. Install the native-build tools:

   ```sh
   brew install cmake git-lfs
   ```

4. Ensure Git and Python 3.9+ are available in the terminal. If Python is missing, install it with `brew install python`. Setup reports missing commands before downloading the engine. Git LFS is required even though large upstream example datasets are skipped; a configured LFS filter still invokes the executable.

XcodeGen is optional for the normal workflow, which uses the included `.xcodeproj`. Install it with `brew install xcodegen` only when you need to regenerate that project.

## Get the source and prepare dependencies

For a Git checkout:

```sh
git clone https://github.com/Dominik-Hagmann/lidar-scanner-ios.git
cd lidar-scanner-ios
bash scripts/setup.sh --open
```

Alternatively, extract GitHub’s source ZIP into a new folder, open Terminal in that folder, and run `bash scripts/setup.sh --open`. Keep older project folders until their local changes have been accounted for.

Setup performs these steps:

1. Check the tools, iOS/macOS SDKs and Metal compiler.
2. Build the pinned Gaussian engine in a separate staging folder, or reuse a verified matching build.
3. Verify the iPhone and Simulator native libraries and both shader resources.
4. Resolve Swift packages using the committed `Package.resolved` versions.
5. Open `LiDARScanner.xcodeproj` when `--open` was supplied.

The first build requires internet access and can take several minutes. The app itself processes scans offline. Setup does not install, launch or delete the app on a phone.

Useful commands, run from the project folder:

| Command | Effect |
| --- | --- |
| `bash scripts/setup.sh --check` | Check prerequisites without downloading or changing project files |
| `bash scripts/setup.sh` | Prepare native and Swift dependencies, preserving the existing Xcode project |
| `bash scripts/setup.sh --open` | Prepare dependencies, then open Xcode |
| `bash scripts/prepare-gaussians.sh` | Prepare only the native engine, without Swift package resolution |
| `bash scripts/setup.sh --regenerate-project` | Back up and regenerate the Xcode project using XcodeGen |

`scripts/bootstrap.sh` is an alias for setup with `--open`.

## Sign and run on a device

1. Open `LiDARScanner.xcodeproj` and add your Apple Account under **Xcode → Settings → Accounts**.
2. Select **Target LiDARScanner → Signing & Capabilities**. Choose your **Team** and keep **Automatically manage signing** enabled.
3. For a genuinely new installation, resolve any bundle-identifier ownership error with an identifier belonging to your team. For an existing installation, keep its original Team and Bundle Identifier so you target the same app and archive.
4. Connect and unlock your LiDAR-equipped iPhone or iPad. Confirm the connection and enable Developer Mode if Xcode requests it.
5. Select the physical device as the destination for the **LiDARScanner** scheme, then press **⌘R**. Grant camera access when the app requests it.

The device needs iOS/iPadOS 18 or later. A Simulator build checks integration but cannot capture LiDAR data. Apple documents [running on devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) and [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Update an existing installation

1. Copy saved scans from the app’s Files location to a separate backup. Point clouds use `Scans`; Gaussian captures use `GaussianScans`. Keep the installed app.
2. Record the Team and Bundle Identifier used for that installation. Close the project before changing its source files.
3. Run `git status` in the existing checkout. Save local changes and untracked work in a separate backup or commit before updating. Avoid a hard reset or clean command. If changes overlap with upstream, resolve them explicitly rather than overwriting them.
4. With a clean working tree on `main`, update without creating an accidental merge:

   ```sh
   git pull --ff-only origin main
   bash scripts/setup.sh
   ```

   If fast-forwarding is refused, stop and inspect the branch history. For ZIP-based copies, extract a new folder and compare local changes before transferring signing settings.

5. Open the updated project. Confirm the original Team, Bundle Identifier and physical device, then press **⌘R** to install over the existing app. Verify that its saved archive remains available.

Default setup leaves the existing `.xcodeproj` intact. Updating source with Git can still change a tracked project file, so the signing check remains necessary.

## Regenerate the Xcode project only when needed

The build definition is in `project.yml`; the generated `.xcodeproj` is committed so ordinary users do not need XcodeGen. Developers changing targets, resources or build settings should regenerate with:

```sh
brew install xcodegen
bash scripts/setup.sh --regenerate-project
```

The previous project, including local settings, is copied to a unique folder under `Dependencies/preserved/`. Regeneration can replace personal signing choices; reapply the original Team before updating an installed app. The committed Swift package lock is retained.

Never copy an old project file wholesale over a newer project without comparing it: doing so can remove newly required targets, packages or resources.
