"""Offline setup regression tests: real temporary Git repos, fixture native outputs."""
import contextlib
import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("prepare_engine", ROOT / "scripts/prepare-gaussians.py")
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)

BUILDER = '''#!/bin/bash
set -euo pipefail
if [[ "${FAIL_NATIVE:-}" == 1 ]]; then exit 7; fi
python3 - <<'PY'
from pathlib import Path
import os, plistlib
root = Path('MsplatCore.xcframework')
libraries = []
for name, variant in [('ios-arm64', ''), ('ios-arm64-simulator', 'simulator')]:
    folder = root / name
    folder.mkdir(parents=True)
    (folder / 'libmsplat_core.a').write_bytes(b'fixture native library')
    entry = dict(LibraryIdentifier=name, LibraryPath='libmsplat_core.a',
                 SupportedArchitectures=['arm64'], SupportedPlatform='ios')
    if variant: entry['SupportedPlatformVariant'] = variant
    libraries.append(entry)
(root / 'Info.plist').write_bytes(plistlib.dumps(dict(AvailableLibraries=libraries)))
resources = Path('swift/Sources/Msplat/Resources')
resources.mkdir(parents=True)
for name in ['default-ios.metallib', 'default-iossimulator.metallib']:
    if name != os.environ.get('OMIT_SHADER'):
        (resources / name).write_bytes(b'fixture shader library')
PY
'''


class NativeSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lidar-setup-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "project with spaces"
        (self.root / "scripts").mkdir(parents=True)
        shutil.copy(ROOT / "scripts/prepare-gaussians.py", self.root / "scripts")
        (self.root / "scripts/patch-engine.py").write_text(
            "from pathlib import Path\nimport sys\np=Path(sys.argv[1])/'source.cpp'\n"
            "p.write_text(p.read_text().replace('original', 'integrated'))\n")
        self.upstream = self.base / "upstream"
        (self.upstream / "scripts").mkdir(parents=True)
        (self.upstream / "scripts/build-xcframework.sh").write_text(
            BUILDER.replace("python3 -", shlex.quote(sys.executable) + " -"))
        (self.upstream / "source.cpp").write_text("original source\n")
        self.environment = patch.dict(os.environ, {
            "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Setup Test", "GIT_AUTHOR_EMAIL": "setup@example.invalid",
            "GIT_COMMITTER_NAME": "Setup Test", "GIT_COMMITTER_EMAIL": "setup@example.invalid",
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.git("init")
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        self.revision = self.git("rev-parse", "HEAD")
        self.builds = 0
        self.toolchain = "Fixture Xcode 1"
        self.builder_environment = None
        self.fake_run = patch.object(engine, "run", side_effect=self.run_command)
        self.fake_run.start()
        self.addCleanup(self.fake_run.stop)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.upstream, text=True,
                                       stderr=subprocess.DEVNULL).strip()

    def run_command(self, *args, cwd=None, capture=False, environment=None):
        if args[0] == "xcodebuild": return self.toolchain
        if args[0] == "xcode-select": return "/Fixture/Xcode.app/Contents/Developer"
        if args[0] == "cmake": return "cmake version 3.25.0"
        if args[0] == "xcrun": return "18.0"
        if args[0] == "bash":
            self.builds += 1
            self.builder_environment = environment
        env = dict(os.environ, GIT_LFS_SKIP_SMUDGE="1")
        env.update(environment or {})
        result = subprocess.run(args, cwd=cwd, env=env, text=True, check=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.stdout.strip() if capture else None

    @property
    def active(self):
        return self.root / "Dependencies/msplat"

    def prepare(self):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            engine.prepare(self.root, self.revision, str(self.upstream))

    def preserved(self):
        return list((self.root / "Dependencies/preserved").glob("*/msplat"))

    def test_first_build_then_verified_cache_reuse(self):
        self.prepare()
        self.prepare()
        self.assertEqual(self.builds, 1)
        self.assertEqual((self.active / "source.cpp").read_text(), "integrated source\n")
        self.assertEqual(self.builder_environment["DEVELOPER_DIR"],
                         "/Fixture/Xcode.app/Contents/Developer")

    def test_incomplete_old_checkout_and_untracked_work_are_preserved(self):
        self.active.mkdir(parents=True)
        (self.active / "local-notes.txt").write_text("do not lose this")
        self.prepare()
        self.assertEqual((self.preserved()[0] / "local-notes.txt").read_text(), "do not lose this")
        self.assertTrue((self.active / engine.MANIFEST).is_file())

    def test_failed_build_leaves_previous_tree_and_retry_succeeds(self):
        self.active.mkdir(parents=True)
        (self.active / "local-notes.txt").write_text("keep")
        with patch.dict(os.environ, {"FAIL_NATIVE": "1"}):
            with self.assertRaises(subprocess.CalledProcessError): self.prepare()
        self.assertEqual((self.active / "local-notes.txt").read_text(), "keep")
        self.assertTrue(list((self.root / "Dependencies").glob(".msplat-build-*")))
        self.prepare()
        self.assertEqual((self.preserved()[0] / "local-notes.txt").read_text(), "keep")

    def test_clone_failure_keeps_previous_dependency(self):
        self.active.mkdir(parents=True)
        (self.active / "local.txt").write_text("keep")
        with self.assertRaises(subprocess.CalledProcessError):
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                engine.prepare(self.root, self.revision, str(self.base / "missing-repository"))
        self.assertEqual((self.active / "local.txt").read_text(), "keep")

    def test_missing_build_output_is_never_promoted(self):
        with patch.dict(os.environ, {"OMIT_SHADER": "default-iossimulator.metallib"}):
            with self.assertRaises(ValueError): self.prepare()
        self.assertFalse(self.active.exists())

    def test_missing_cached_shader_triggers_rebuild(self):
        self.prepare()
        (self.active / engine.SHADERS[1]).unlink()
        self.prepare()
        self.assertEqual(self.builds, 2)
        self.assertTrue((self.active / engine.SHADERS[1]).is_file())

    def test_corrupted_cached_library_triggers_rebuild(self):
        self.prepare()
        binary = self.active / "MsplatCore.xcframework/ios-arm64/libmsplat_core.a"
        binary.write_bytes(b"corrupted")
        self.prepare()
        self.assertEqual(self.builds, 2)
        self.assertEqual(binary.read_bytes(), b"fixture native library")

    def test_toolchain_change_invalidates_cache(self):
        self.prepare()
        self.toolchain = "Fixture Xcode 2"
        self.prepare()
        self.assertEqual(self.builds, 2)

    def test_local_source_edits_are_preserved_before_clean_rebuild(self):
        self.prepare()
        (self.active / "source.cpp").write_text("user edit")
        self.prepare()
        self.assertEqual((self.preserved()[0] / "source.cpp").read_text(), "user edit")
        self.assertEqual((self.active / "source.cpp").read_text(), "integrated source\n")

    def test_bad_cache_metadata_is_rebuilt(self):
        self.prepare()
        (self.active / engine.MANIFEST).write_text('{"artifacts":null}')
        self.prepare()
        self.assertEqual(self.builds, 2)

    def test_simultaneous_native_setup_is_refused(self):
        (self.root / "Dependencies").mkdir()
        with (self.root / "Dependencies/.prepare-gaussians.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, "Another Gaussian setup"):
                self.prepare()
        self.assertEqual(self.builds, 0)

    def test_promotion_failure_restores_previous_tree(self):
        self.active.mkdir(parents=True)
        (self.active / "local.txt").write_text("keep")
        original_rename = Path.rename
        def failing_rename(path, target):
            if path.parent.name.startswith(".msplat-build-"):
                raise OSError("fixture promotion error")
            return original_rename(path, target)
        with patch.object(Path, "rename", failing_rename):
            with self.assertRaises(OSError): self.prepare()
        self.assertEqual((self.active / "local.txt").read_text(), "keep")


class SetupEntryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lidar-entry-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "project with spaces"
        shutil.copytree(ROOT / "scripts", self.root / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
        # Never build real dependencies from shell entry tests.
        (self.root / "scripts/prepare-gaussians.py").write_text("print('fixture native preparation')\n")
        self.project = self.root / "LiDARScanner.xcodeproj"
        self.lock = self.project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        self.lock.parent.mkdir(parents=True)
        self.lock.write_text('{"pins":[]}\n')
        (self.project / "project.pbxproj").write_text("personal signing settings\n")
        self.bin = self.root / "test-bin"
        self.bin.mkdir()
        self.calls = self.root / "tool-calls.txt"
        self.env = dict(os.environ, PATH=str(self.bin), CALLS_FILE=str(self.calls))
        for tool in ("bash", "dirname", "head", "cp", "mkdir", "mktemp"):
            (self.bin / tool).symlink_to(shutil.which(tool))
        (self.bin / "python3").symlink_to(sys.executable)
        self.stub("uname", "echo Darwin")
        self.stub("git", "echo git-lfs-fixture")
        self.stub("git-lfs", ":")
        self.stub("cmake", "echo 'cmake version 3.25.0'")
        self.stub("xcode-select", "echo /Fixture/Xcode.app/Contents/Developer")
        self.stub("xcrun", "echo fixture-sdk")
        self.stub("xcodebuild", 'echo "$*" >> "$CALLS_FILE"; echo "Xcode 16.4"')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -e\n" + body + "\n")
        path.chmod(0o755)

    def setup(self, *args):
        return subprocess.run(["/bin/bash", "scripts/setup.sh", *args], cwd=self.root,
                              env=self.env, text=True, capture_output=True)

    def test_check_does_not_download_or_change_project(self):
        result = self.setup("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "Dependencies").exists())
        self.assertEqual((self.project / "project.pbxproj").read_text(), "personal signing settings\n")
        self.assertNotIn("resolvePackage", self.calls.read_text())

    def test_missing_git_lfs_fails_before_download(self):
        (self.bin / "git-lfs").unlink()
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing command: git-lfs", result.stderr)
        self.assertFalse((self.root / "Dependencies").exists())

    def test_missing_metal_fails_before_download(self):
        self.stub("xcrun", 'if [[ "$3" == metal ]]; then exit 1; fi; echo fixture-sdk')
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Metal compiler", result.stderr)
        self.assertFalse((self.root / "Dependencies").exists())

    def test_unsupported_xcode_fails_before_download(self):
        self.stub("xcodebuild", 'echo "Xcode 15.4"')
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Xcode 16.4 or newer", result.stderr)
        self.assertFalse((self.root / "Dependencies").exists())

    def test_default_preserves_signing_without_xcodegen(self):
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.project / "project.pbxproj").read_text(), "personal signing settings\n")
        self.assertIn("-onlyUsePackageVersionsFromResolvedFile", self.calls.read_text())

    def test_regeneration_requires_xcodegen_before_download(self):
        result = self.setup("--regenerate-project")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing command: xcodegen", result.stderr)
        self.assertFalse((self.root / "Dependencies").exists())

    def test_explicit_regeneration_backs_up_signing_and_keeps_lock(self):
        self.stub("xcodegen", 'echo generated > LiDARScanner.xcodeproj/project.pbxproj')
        result = self.setup("--regenerate-project")
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list((self.root / "Dependencies/preserved").glob("*/LiDARScanner.xcodeproj/project.pbxproj"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "personal signing settings\n")
        self.assertEqual(self.lock.read_text(), '{"pins":[]}\n')

    def test_missing_lock_is_reported_before_native_preparation(self):
        self.lock.unlink()
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lockfile is missing", result.stderr)
        self.assertNotIn("fixture native preparation", result.stdout)

    def test_failed_package_resolution_does_not_open_xcode(self):
        self.stub("xcodebuild", 'if [[ "$1" != -version ]]; then exit 8; fi; echo "Xcode 16.4"')
        self.stub("open", 'echo opened >> "$CALLS_FILE"')
        result = self.setup("--open")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
