#!/usr/bin/env python3
"""Small safety checks for the physical-deletion harness, without invoking Xcode."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


sys.dont_write_bytecode = True
SCRIPT = Path(__file__).with_name("test-module-removal.py")
module_spec = importlib.util.spec_from_file_location("module_removal", SCRIPT)
harness = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(harness)


class RemovalSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="neodizzy-removal-harness-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.source = self.base / "checkout"
        self.source.mkdir()
        self.spec = harness.load_spec(SCRIPT.with_name("module-removal-manifest.json"))
        self.write("NeoDizzy.xcodeproj/project.pbxproj", "fixture project\n")
        self.write("NeoDizzy/App/Modules/AppComposition.swift", """enum AppComposition {
    static let registrations = [
        DizzyLabModule.registration,
        NeteaseModule.registration,
        QQMusicModule.registration,
        LocalLibraryModule.registration,
    ]
}
""")
        for identifier, module in self.spec["modules"].items():
            self.write(module["source_paths"][0] + "/API.swift", f"struct {identifier}API {{}}\n")
            self.write(module["source_paths"][1] + "/Views.swift", f"struct {identifier}View {{}}\n")
            self.write(module["test_paths"][0] + "/OwnedTests.swift", f"// {identifier} tests\n")
            raw_id = {"dizzylab": "dizzyLab", "netease": "netease", "qqmusic": "qqmusic"}[identifier]
            self.write(module["module_id_source"], f'extension ModuleID {{ static let platform = ModuleID(rawValue: "{raw_id}") }}\n')
        self.write(self.spec["local_module_id_source"], 'extension ModuleID { static let localLibrary = ModuleID(rawValue: "localLibrary") }\n')
        self.write("NeoDizzy/Core/Library/Host.swift", "struct Host {}\n")
        self.write("NeoDizzyTests/HostTests.swift", "// shared tests retained\n")
        self.write("NeoDizzy/Core/Untracked.swift", "// untracked current work\n")
        self.write("Packages/AudioTags/.build/large-cache", "do not copy\n")
        (self.source / "NeoDizzy/Features/Tags").mkdir(parents=True)

    def write(self, relative, value):
        path = self.source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def prepare(self, name):
        case_dir = self.base / "matrix" / name
        with contextlib.redirect_stdout(io.StringIO()):
            report = harness.prepare(self.source, case_dir, name, self.spec,
                                     SCRIPT.with_name("module-removal-manifest.json"))
        return case_dir, report

    def test_all_four_cases_delete_real_module_files_and_preserve_other_sources(self):
        before = harness.inventory(self.source)
        for name, removed in harness.CASES.items():
            with self.subTest(case=name):
                case_dir, report = self.prepare(name)
                snapshot = case_dir / "source"
                self.assertEqual(report["deleted_product_swift_count"], 3 * len(removed))
                self.assertEqual(report["deleted_test_swift_count"], len(removed))
                self.assertEqual((snapshot / "NeoDizzy/Core/Library/Host.swift").read_bytes(),
                                 (self.source / "NeoDizzy/Core/Library/Host.swift").read_bytes())
                self.assertTrue((snapshot / "NeoDizzyTests/HostTests.swift").is_file())
                self.assertTrue((snapshot / "NeoDizzy/Core/Untracked.swift").is_file())
                self.assertFalse((snapshot / "Packages/AudioTags/.build").exists())
                self.assertTrue((snapshot / "NeoDizzy/Features/Tags").is_dir())
                for identifier, module in self.spec["modules"].items():
                    present = (snapshot / module["source_paths"][0] / "API.swift").exists()
                    self.assertEqual(present, identifier not in removed)
                harness.validate_snapshot(case_dir)
                expected = [identifier for identifier in ("dizzyLab", "netease", "qqmusic")
                            if identifier.lower() not in removed] + ["localLibrary"]
                self.assertEqual(report["expected_module_ids"], expected)
        self.assertEqual(harness.inventory(self.source), before)

    def test_prepared_copy_cannot_be_modified_or_have_code_restored(self):
        case_dir, _ = self.prepare("remove-all")
        host = case_dir / "source/NeoDizzy/Core/Library/Host.swift"
        host.write_text("struct ChangedHost {}\n")
        with self.assertRaisesRegex(ValueError, "Prepared source changed"):
            harness.validate_snapshot(case_dir)

    def test_missing_registration_is_rejected_instead_of_rewriting_other_code(self):
        with self.assertRaisesRegex(ValueError, "exactly one"):
            harness.rewrite_composition("let unrelated = LocalLibraryModule.registration\n", ("qqmusic",), self.spec)

    def test_copy_is_never_overwritten(self):
        self.prepare("remove-qqmusic")
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.prepare("remove-qqmusic")

    def test_cli_rejects_output_in_checkout(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--case", "all", "--prepare-only",
                                 "--source-root", str(self.source), "--output-root", str(self.source / "out")],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("outside", result.stderr)
        self.assertFalse((self.source / "out").exists())

    def test_manifest_cannot_delete_host_root_or_escape_checkout(self):
        for path in ("../NeoDizzy", "NeoDizzy", "/tmp/module", "NeoDizzy/Core", "NeoDizzy/Features/Modules/Netease"):
            spec = json.loads(json.dumps(self.spec))
            spec["modules"]["qqmusic"]["source_paths"] = [path]
            manifest = self.base / "unsafe.json"
            manifest.write_text(json.dumps(spec))
            with self.subTest(path=path), self.assertRaises(ValueError):
                harness.load_spec(manifest)

    def test_joint_integration_test_is_removed_only_when_a_required_module_is_removed(self):
        relative = "NeoDizzyTests/Modules/Integration/IntegrationTransportIsolationTests.swift"
        self.write(relative, "// requires both DizzyLab and Netease\n")
        for case_name in harness.CASES:
            with self.subTest(case=case_name):
                case_dir, _ = self.prepare(case_name)
                self.assertEqual((case_dir / "source" / relative).exists(), case_name == "remove-qqmusic")

    def test_project_rewrite_only_removes_exact_module_membership_exception_entries(self):
        project = """/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
        AAAAAAAAAAAAAAAAAAAAAAAA /* PBXFileSystemSynchronizedBuildFileExceptionSet */ = {
            isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
            membershipExceptions = (
                Core/UI/Host.swift,
                Features/Modules,
                Features/Modules/QQMusic,
                Features/Modules/QQMusic/QQMusicViews.swift,
                Features/Modules/QQMusicOther/Unrelated.swift,
                Features/Modules/Netease/Survivor.swift,
            );
            target = 111111111111111111111111 /* Mac */;
        };
        BBBBBBBBBBBBBBBBBBBBBBBB /* PBXFileSystemSynchronizedBuildFileExceptionSet */ = {
            isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
            membershipExceptions = (
                Features/Modules/QQMusic/NotInAppFolder.swift,
            );
            target = 111111111111111111111111 /* Mac */;
        };
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */
/* Begin PBXFileSystemSynchronizedRootGroup section */
        CCCCCCCCCCCCCCCCCCCCCCCC /* NeoDizzy */ = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (AAAAAAAAAAAAAAAAAAAAAAAA /* PBXFileSystemSynchronizedBuildFileExceptionSet */, ); explicitFileTypes = {}; explicitFolders = (); path = NeoDizzy; sourceTree = "<group>"; };
/* End PBXFileSystemSynchronizedRootGroup section */
"""
        rewritten, removed = harness.rewrite_project_membership(project, ["NeoDizzy/Features/Modules/QQMusic"])
        self.assertEqual(removed, ["Features/Modules/QQMusic", "Features/Modules/QQMusic/QQMusicViews.swift"])
        for path in removed:
            project = project.replace("                " + path + ",\n", "")
        self.assertEqual(rewritten, project)

    def test_runtime_contract_marker_is_required_and_must_match_both_module_sets(self):
        case_dir, _ = self.prepare("remove-all")
        self.assertFalse(harness.verify_test_environment(case_dir)["verified"])
        products = case_dir / "artifacts/DerivedData/Build/Products"
        products.mkdir(parents=True)
        configuration = {"TestConfigurations": [{"TestTargets": [{"EnvironmentVariables": {
            "REMOVAL_EXPECTED_MODULES": "localLibrary"
        }}]}]}
        xctestrun = products / "fixture.xctestrun"
        xctestrun.write_bytes(plistlib.dumps(configuration))
        self.assertFalse(harness.verify_test_environment(case_dir)["verified"], "A test plan alone cannot prove Swift saw the environment")
        log = case_dir / "artifacts/xcodebuild.log"
        log.write_text("ModuleRemovalContract expected=localLibrary actual=localLibrary\n")
        evidence = harness.verify_test_environment(case_dir)
        self.assertTrue(evidence["verified"])
        self.assertEqual(evidence["verifiedBy"], "runtime-contract-output")
        log.write_text("ModuleRemovalContract expected=localLibrary actual=wrong-module\n")
        self.assertFalse(harness.verify_test_environment(case_dir)["verified"])
        log.write_text("ModuleRemovalContract expected=wrong-module actual=localLibrary\n")
        self.assertFalse(harness.verify_test_environment(case_dir)["verified"])

    def test_reuses_only_same_case_stopped_cache_with_new_snapshot_and_results(self):
        case_dir, _ = self.prepare("remove-all")
        previous = self.base / "previous/remove-all/artifacts"
        products = previous / "DerivedData/Build/Products"
        products.mkdir(parents=True)
        (previous / "SourcePackages").mkdir()
        args = SimpleNamespace(reuse_build_cache=self.base / "previous", seed_packages=None,
                               destination="fixture-simulator", jobs=1, timeout=30)
        commands = []

        def run(command, **_kwargs):
            commands.append(command)
            if command[0] == "xcodebuild":
                (case_dir / "artifacts/Tests.xcresult").mkdir()
                (case_dir / "artifacts/xcodebuild.log").write_text("ModuleRemovalContract expected=localLibrary actual=localLibrary\n")
                return subprocess.CompletedProcess(command, 0)
            return subprocess.CompletedProcess(command, 0, stdout=json.dumps({"totalTestCount": 1, "failedTests": 0}))

        with patch.object(harness.subprocess, "run", side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(harness.run_tests(case_dir, args), 0)
        result = json.loads((case_dir / "artifacts/result.json").read_text())
        self.assertEqual(result["derived_data_path"], str(previous / "DerivedData"))
        self.assertEqual(result["source_packages_path"], str(previous / "SourcePackages"))
        self.assertIn(str(case_dir / "source/NeoDizzy.xcodeproj"), commands[0])
        self.assertTrue(result["actual_test_environment_verified"])
        self.assertFalse((previous / "reuse-build-cache.lock").exists())
        self.assertFalse((previous / "result.json").exists())
        self.assertTrue((case_dir / "artifacts/expected-environment.json").is_file())

    def test_reused_cache_lock_owned_by_another_run_is_never_removed(self):
        case_dir, _ = self.prepare("remove-all")
        previous = self.base / "previous/remove-all/artifacts"
        (previous / "DerivedData").mkdir(parents=True)
        (previous / "SourcePackages").mkdir()
        lock = previous / "reuse-build-cache.lock"
        lock.write_text("another process")
        args = SimpleNamespace(reuse_build_cache=self.base / "previous", seed_packages=None,
                               destination="fixture-simulator", jobs=1, timeout=30)
        with self.assertRaises(FileExistsError):
            harness.run_tests(case_dir, args)
        self.assertEqual(lock.read_text(), "another process")



if __name__ == "__main__":
    unittest.main()
