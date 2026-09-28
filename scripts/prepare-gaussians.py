"""Build a pinned engine in isolation and preserve the previous dependency tree."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

REVISION = "e8611098583059b82e0b7d35259fb4e9c42df248"
SOURCE = "https://github.com/frs0n/msplat-ios.git"
MANIFEST = ".scanner-build.json"
SHADERS = (
    "swift/Sources/Msplat/Resources/default-ios.metallib",
    "swift/Sources/Msplat/Resources/default-iossimulator.metallib",
)


def run(*args, cwd=None, capture=False, environment=None):
    env = dict(os.environ, GIT_LFS_SKIP_SMUDGE="1")
    env.update(environment or {})
    result = subprocess.run(args, cwd=cwd, env=env, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def fingerprint(root, revision, source):
    return {
        "revision": revision,
        "source": source,
        "patch": digest(root / "scripts/patch-engine.py"),
        "preparation": digest(root / "scripts/prepare-gaussians.py"),
        "xcode": run("xcodebuild", "-version", capture=True),
        "developer_dir": os.environ.get("DEVELOPER_DIR") or run("xcode-select", "-p", capture=True),
        "cmake": run("cmake", "--version", capture=True).splitlines()[0],
        "sdks": {sdk: run("xcrun", "--sdk", sdk, "--show-sdk-version", capture=True)
                 for sdk in ("macosx", "iphoneos", "iphonesimulator")},
        "deployment": {name: os.environ.get(name, default) for name, default in
                       (("IOS_DEPLOYMENT_TARGET", "18.0"), ("MACOS_DEPLOYMENT_TARGET", "15.0"))},
    }


def source_hashes(engine):
    # Include locally patched tracked files, so source edits invalidate the cache.
    names = run("git", "ls-files", "-z", cwd=engine, capture=True).split("\0")
    return {name: digest(engine / name) for name in names if name}


def artifact_hashes(engine):
    framework = engine / "MsplatCore.xcframework"
    with (framework / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    supported = set()
    for library in info["AvailableLibraries"]:
        relative = Path(library["LibraryIdentifier"]) / library["LibraryPath"]
        binary = framework / relative
        if not binary.resolve().is_relative_to(framework.resolve()):
            raise ValueError("Invalid XCFramework library path")
        if not binary.is_file() or binary.stat().st_size == 0:
            raise ValueError(f"Missing or empty native library: {relative}")
        if "arm64" in library["SupportedArchitectures"]:
            supported.add((library["SupportedPlatform"], library.get("SupportedPlatformVariant", "")))
    if not {("ios", ""), ("ios", "simulator")} <= supported:
        raise ValueError("XCFramework must contain arm64 iPhone and Simulator libraries")
    paths = [path for path in framework.rglob("*") if path.is_file()]
    for relative in SHADERS:
        path = engine / relative
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing or empty shader library: {relative}")
        paths.append(path)
    return {str(path.relative_to(engine)): digest(path) for path in paths}


def reusable(engine, expected):
    try:
        manifest = json.loads((engine / MANIFEST).read_text())
        return (manifest["fingerprint"] == expected
                and run("git", "rev-parse", "HEAD", cwd=engine, capture=True) == expected["revision"]
                and manifest["sources"] == source_hashes(engine)
                and manifest["artifacts"] == artifact_hashes(engine))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        return False


def prepare(root, revision=REVISION, source=SOURCE):
    dependencies = root / "Dependencies"
    dependencies.mkdir(exist_ok=True)
    with (dependencies / ".prepare-gaussians.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another Gaussian setup is running in this checkout. Wait for it to finish.")
        expected = fingerprint(root, revision, source)
        engine = dependencies / "msplat"
        if reusable(engine, expected):
            print("Verified native libraries and shaders match the source and selected toolchain.", flush=True)
            return
        stage = Path(tempfile.mkdtemp(prefix=".msplat-build-", dir=dependencies))
        candidate = stage / "msplat"
        print(f"Preparing the pinned engine in {stage}", flush=True)
        try:
            run("git", "clone", "--no-checkout", source, str(candidate))
            run("git", "checkout", "--detach", revision, cwd=candidate)
            run(sys.executable, str(root / "scripts/patch-engine.py"), str(candidate))
            run("bash", "scripts/build-xcframework.sh", cwd=candidate,
                environment={"DEVELOPER_DIR": expected["developer_dir"]})
            manifest = {"fingerprint": expected, "sources": source_hashes(candidate),
                        "artifacts": artifact_hashes(candidate)}
            (candidate / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
            preserved = None
            if engine.exists() or engine.is_symlink():
                archive = dependencies / "preserved"
                archive.mkdir(exist_ok=True)
                stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                preserved = Path(tempfile.mkdtemp(prefix=f"msplat-{stamp}-", dir=archive)) / "msplat"
                engine.rename(preserved)
                print(f"Previous dependency files preserved at {preserved}", flush=True)
            try:
                candidate.rename(engine)
            except BaseException:
                if preserved is not None and not engine.exists():
                    preserved.rename(engine)
                raise
            stage.rmdir()  # Only the now-empty staging directory, never user files.
        except BaseException:
            print(f"Setup did not finish. Build files remain at {stage}; rerunning setup starts a new isolated attempt.", file=sys.stderr)
            raise
        print("Native libraries and both shader libraries verified and ready.", flush=True)


if __name__ == "__main__":
    try:
        prepare(Path(__file__).resolve().parent.parent)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f"Gaussian setup failed: {error}")
