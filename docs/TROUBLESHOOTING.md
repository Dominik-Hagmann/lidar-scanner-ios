# Troubleshooting

[Back to the README](../README.md) · [Installation and updates](INSTALLATION.md)

## Check the Mac before retrying

Run `bash scripts/setup.sh --check` from the project folder. This checks the tools and SDKs without downloading dependencies or changing the project. Fix the reported prerequisite, then rerun `bash scripts/setup.sh`.

## Missing commands or Metal compiler

- **`cmake` or `git-lfs`:** install them with `brew install cmake git-lfs`. If already installed, check that Homebrew’s `bin` directory is on your terminal’s `PATH`; follow the “Next steps” printed by the Homebrew installer.
- **`xcodegen`:** required only for project generation. Install it with `brew install xcodegen` when using `--regenerate-project`.
- **Xcode, an SDK or the Metal compiler:** open the full Xcode application and complete its first launch and required component installation. Check Xcode → Settings → Locations for the selected Command Line Tools. Command Line Tools alone do not provide the complete iOS build environment. If Xcode reports a missing Metal Toolchain, install that component through Xcode before retrying.
- **Python:** setup requires Python 3.9 or newer on `PATH`.

If Xcode specifically reports “cannot execute tool 'metal' due to missing Metal Toolchain”, its suggested installation command is:

```sh
xcodebuild -downloadComponent MetalToolchain
```

This downloads an Xcode component. Complete it before rerunning the prerequisite check; setup does not trigger component installation automatically.

## Interrupted download or native build

Fix the reported network or compiler error and rerun `bash scripts/setup.sh`. Each unsuccessful native build stays in a separate `Dependencies/.msplat-build-*` folder. A retry uses a new staging folder and leaves the previous `Dependencies/msplat` untouched until all required native outputs have been verified.

On success, any previous dependency folder moves to the printed path under `Dependencies/preserved/`. This also preserves incomplete older checkouts and local edits. Those edits are not applied to the newly built, pinned source. Nothing in the setup scripts deletes phone scans or uncommitted app source files. Failed and preserved build folders use disk space; inspect them before removing any manually.

If another setup is running in the same checkout, wait for it to finish. The native-build lock releases when the process exits; an empty lock file may remain and does not block later runs.

## Missing libraries or stale build cache

Run `bash scripts/setup.sh` before building in Xcode. The native cache is reused only when the selected Xcode/SDKs, source revision, integration scripts, tracked source files and required output hashes match. A missing shader, changed compiler configuration or damaged library triggers a fresh isolated build.

Swift packages are resolved separately from the committed `Package.resolved`. If resolution fails, check the error and network access; do not delete the lockfile to select arbitrary newer versions.

## App no longer available

If iOS or iPadOS displays **“App is no longer available”** (German: **„App ist nicht mehr verfügbar“**; wording may vary) when you tap the app icon, try the following steps for an installation made through Xcode.

**Protect existing scans first:** Do not delete the installed app as a troubleshooting step: [deleting an app also removes its local data](https://support.apple.com/guide/iphone/remove-or-delete-apps-iph248b543ca/ios). If the scan folder is accessible, copy **Files → On My iPhone / On My iPad → LiDAR-Scanner → Scans** to iCloud Drive or a Mac before proceeding.

1. Connect the iPhone or iPad to the Mac and unlock it.
2. Open the same `LiDARScanner.xcodeproj` used for the original installation and select the physical device as the destination, not the Simulator.
3. Under **Target LiDARScanner → Signing & Capabilities**, keep the **same Team and Bundle Identifier** used for the installed app and enable **Automatically manage signing**. Do not switch accounts or change the identifier merely to troubleshoot this launch error.
4. Select **Run** or press **⌘R** to rebuild, sign, and deploy the app again without first deleting it.
5. After a successful run, check the scan archive and confirm that the app opens from its Home Screen icon again.

**Why this may help:** The app's signing or provisioning may no longer be valid. For an installation made using a free Apple Account (**Personal Team** in Xcode), an expired provisioning profile is a likely explanation, especially if the app worked previously and stopped opening after several days. Apple states that these profiles expire **7 days after issuance**, after which the app must be rebuilt and reinstalled; see [Developer account overview → Enable a personal team in Xcode](https://developer.apple.com/help/account/basics/about-your-developer-account). This is an Apple provisioning restriction, not a time limit implemented by LiDAR Scanner.

**If the app still does not open:** Check the exact signing or installation error in Xcode before making further changes. The iOS/iPadOS message alone does not confirm that the provisioning profile has expired. Reinstalling over the existing app is not a substitute for a separate backup of exported scans.
