#!/usr/bin/env python3
"""Physically remove platform code from isolated copies and test every survivor.

Examples (use a different simulator for each concurrent test process):
  python3 scripts/test-module-removal.py --case all --output-root /tmp/removal --prepare-only
  python3 scripts/test-module-removal.py --case remove-qqmusic --output-root /tmp/removal \
      --run-prepared --destination 'platform=iOS Simulator,id=SIMULATOR-UUID'

This deliberately does not use a git worktree: uncommitted and untracked source
files are part of the application under review. No source is deleted in the
working checkout. Only composition-root registrations and exact removed-platform
project membership exceptions are rewritten; all other retained inputs must
remain byte-identical to the captured snapshot.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
CASES = {
    "remove-dizzylab": ("dizzylab",),
    "remove-netease": ("netease",),
    "remove-qqmusic": ("qqmusic",),
    "remove-all": ("dizzylab", "netease", "qqmusic"),
}
COPY_ROOTS = (
    "NeoDizzy", "NeoDizzyWidget", "WidgetShared",
    "NeoDizzyTests", "NeoDizzy.xcodeproj", "Packages", "Config", "scripts", "project.yml",
)
EXCLUDED_NAMES = {".git", ".build", "build", "dist", "xcuserdata", ".DS_Store", "__pycache__"}


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    if path.is_symlink():
        return "symlink:" + os.readlink(path)
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def excluded(name):
    return name in EXCLUDED_NAMES or name.startswith("DerivedData") or name.endswith(".xcresult")


def inventory(root):
    """Enumerate exactly the source/configuration inputs copied for an iOS build."""
    result = {}
    for relative in COPY_ROOTS:
        top = root / relative
        if not top.exists():
            continue
        if top.is_file() or top.is_symlink():
            result[relative] = digest(top)
            continue
        for directory, dirs, files in os.walk(top, followlinks=False):
            dirs[:] = sorted(name for name in dirs if not excluded(name))
            # Store directory symlinks too, but do not traverse or mutate them.
            for name in dirs[:]:
                path = Path(directory) / name
                if path.is_symlink():
                    result[path.relative_to(root).as_posix()] = digest(path)
                    dirs.remove(name)
            for name in sorted(files):
                if not excluded(name):
                    path = Path(directory) / name
                    result[path.relative_to(root).as_posix()] = digest(path)
    return result


def directory_inventory(root):
    """Empty host directories can be referenced by Xcode and are preserved too."""
    result = []
    for relative in COPY_ROOTS:
        top = root / relative
        if not top.is_dir() or top.is_symlink():
            continue
        for directory, dirs, _files in os.walk(top, followlinks=False):
            dirs[:] = sorted(name for name in dirs if not excluded(name)
                             and not (Path(directory) / name).is_symlink())
            result.append(Path(directory).relative_to(root).as_posix())
    return sorted(result)


def safe_relative(value):
    path = Path(value)
    if path.is_absolute() or not path.parts or ".." in path.parts or path == Path("."):
        raise ValueError(f"Unsafe manifest path: {value!r}")
    return path.as_posix()


def load_spec(path):
    spec = json.loads(path.read_text())
    if spec.get("schema_version") != 1 or set(spec.get("modules", {})) != {"dizzylab", "netease", "qqmusic"}:
        raise ValueError("Manifest must use schema_version 1 and declare all three music modules.")
    safe_relative(spec["composition_root"])
    safe_relative(spec["local_module_id_source"])
    directory_names = {"dizzylab": "DizzyLab", "netease": "Netease", "qqmusic": "QQMusic"}
    for identifier, module in spec["modules"].items():
        safe_relative(module["module_id_source"])
        for field in ("source_paths", "test_paths"):
            for value in module.get(field, []):
                safe_relative(value)
                prefix = "NeoDizzyTests/" if field == "test_paths" else "NeoDizzy/"
                if not value.startswith(prefix):
                    raise ValueError(f"{field} must be under {prefix}: {value}")
                if field == "source_paths":
                    name = directory_names[identifier]
                    module_roots = (f"NeoDizzy/Core/Modules/{name}", f"NeoDizzy/Features/Modules/{name}")
                    if not any(value == root or value.startswith(root + "/") for root in module_roots):
                        raise ValueError(f"Refusing to delete host or another platform's source: {value}")
        expression = module["registration"]
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*\.registration", expression):
            raise ValueError(f"Invalid registration expression: {expression}")
    return spec


def owned(relative, paths):
    return any(relative == path or relative.startswith(path.rstrip("/") + "/") for path in paths)


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".new")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def rewrite_composition(source, removed_modules, spec):
    """Remove only exact registration entries, never arbitrary platform references."""
    for identifier in removed_modules:
        expression = spec["modules"][identifier]["registration"]
        pattern = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(expression) + r"\s*,")
        source, count = pattern.subn("", source)
        if count != 1:
            raise ValueError(f"Expected exactly one comma-terminated registration for {identifier}; found {count}.")
    return source


def read_module_id(source_root, relative):
    source = (source_root / relative).read_text()
    values = re.findall(r'static\s+let\s+\w+\s*=\s*ModuleID\(rawValue:\s*"([^"\n,]+)"\)', source)
    if len(values) != 1:
        raise ValueError(f"Expected one actual ModuleID declaration in {relative}; found {len(values)}.")
    return values[0]


def rewrite_project_membership(source, remove_paths):
    """Delete only removed module entries in the NeoDizzy synced-folder exceptions.

    XcodeGen records per-target exclusions in synced-folder membership exceptions.
    A stale entry can make Xcode treat a deleted file as an explicit build input.
    This changes assembly metadata, not a target, build setting, or host source.
    """
    section = re.search(r'/\* Begin PBXFileSystemSynchronizedRootGroup section \*/(.*?)'
                        r'/\* End PBXFileSystemSynchronizedRootGroup section \*/', source, re.DOTALL)
    if not section:
        return source, []
    root_group = re.search(
        r'^\s*[A-F0-9]+ /\* NeoDizzy \*/ = \{.*?isa = PBXFileSystemSynchronizedRootGroup;.*?'
        r'exceptions = \((.*?)\);', section.group(1), re.MULTILINE | re.DOTALL)
    if not root_group:
        return source, []
    exception_ids = set(re.findall(r'\b[A-F0-9]{24}\b', root_group.group(1)))
    removed = []
    pattern = re.compile(
        r'(?P<header>^\s*(?P<id>[A-F0-9]{24}) /\* PBXFileSystemSynchronizedBuildFileExceptionSet \*/ = \{\s*'
        r'isa = PBXFileSystemSynchronizedBuildFileExceptionSet;\s*membershipExceptions = \()'
        r'(?P<entries>.*?)(?P<footer>\);)', re.MULTILINE | re.DOTALL)

    def replace(match):
        if match.group("id") not in exception_ids:
            return match.group()
        kept = []
        for line in match.group("entries").splitlines(keepends=True):
            entry = re.fullmatch(r'\s*(?:"([^"\n]+)"|([^\s",]+)),\s*', line)
            if entry:
                path = entry.group(1) or entry.group(2)
                if owned("NeoDizzy/" + path, remove_paths):
                    removed.append(path)
                    continue
            kept.append(line)
        return match.group("header") + "".join(kept) + match.group("footer")

    return pattern.sub(replace, source), removed


def validate_snapshot(case_dir):
    report = json.loads((case_dir / "removal-manifest.json").read_text())
    snapshot = case_dir / "source"
    actual = inventory(snapshot)
    expected = report["snapshot_after_sha256"]
    if actual != expected:
        changed = sorted(key for key in actual.keys() | expected.keys() if actual.get(key) != expected.get(key))
        raise ValueError("Prepared source changed since capture: " + ", ".join(changed[:20]))
    if "snapshot_after_directories" in report and directory_inventory(snapshot) != report["snapshot_after_directories"]:
        raise ValueError("Prepared directory structure changed since capture.")
    for path in report["deleted_files"]:
        if (snapshot / path).exists() or (snapshot / path).is_symlink():
            raise ValueError(f"Removed code reappeared: {path}")
    return report


def verify_test_environment(case_dir):
    """Require the running Swift contract to report the exact compiled modules."""
    report = validate_snapshot(case_dir)
    expected = ",".join(report["expected_module_ids"])
    artifacts = case_dir / "artifacts"
    result_path = artifacts / "result.json"
    result = json.loads(result_path.read_text()) if result_path.exists() else {}
    derived_data = Path(result.get("derived_data_path", artifacts / "DerivedData"))
    evidence = {"case": report["case"], "expected_value": expected,
                "expected_module_ids": report["expected_module_ids"], "xctestrun_files": [],
                "runtime_contract_matches": [], "verified": False}
    expected_ids = set(report["expected_module_ids"])
    log_path = artifacts / "xcodebuild.log"
    if log_path.exists():
        pattern = re.compile(r'ModuleRemovalContract expected=(?P<expected>\S*) actual=(?P<actual>\S*)')
        for line_number, line in enumerate(log_path.read_text(errors="replace").splitlines(), 1):
            match = pattern.search(line)
            if not match:
                continue
            requested, actual = match.group("expected").split(","), match.group("actual").split(",")
            exact = (len(requested) == len(actual) == len(expected_ids)
                     and set(requested) == set(actual) == expected_ids)
            evidence["runtime_contract_matches"].append({
                "log": str(log_path), "line": line_number, "expected": requested,
                "actual": actual, "exact": exact,
            })

    def walk(value, path, matches):
        if isinstance(value, dict):
            if "REMOVAL_EXPECTED_MODULES" in value:
                matches.append({"key_path": ".".join(path + ["REMOVAL_EXPECTED_MODULES"]),
                                "value": value["REMOVAL_EXPECTED_MODULES"]})
            for key, child in value.items():
                walk(child, path + [str(key)], matches)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, path + [str(index)], matches)

    all_matches = []
    for path in sorted((derived_data / "Build/Products").glob("*.xctestrun")):
        with path.open("rb") as stream:
            configuration = plistlib.load(stream)
        matches = []
        walk(configuration, [], matches)
        evidence["xctestrun_files"].append({"path": str(path), "matches": matches})
        all_matches.extend(matches)
    runtime = evidence["runtime_contract_matches"]
    evidence["verified"] = bool(runtime) and all(match["exact"] for match in runtime)
    if evidence["verified"]:
        evidence["verifiedBy"] = "runtime-contract-output"
    artifacts.mkdir(exist_ok=True)
    write_json(artifacts / "expected-environment.json", evidence)
    return evidence


def prepare(source_root, case_dir, case_name, spec, spec_path):
    if case_dir.exists():
        raise ValueError(f"Output already exists; choose a new output root or use --run-prepared: {case_dir}")
    case_dir.mkdir(parents=True)
    snapshot = case_dir / "source"
    snapshot.mkdir()
    before = inventory(source_root)
    before_directories = directory_inventory(source_root)
    for relative in COPY_ROOTS:
        source = source_root / relative
        target = snapshot / relative
        if not source.exists():
            continue
        if source.is_dir() and not source.is_symlink():
            shutil.copytree(source, target, symlinks=True,
                            ignore=lambda _directory, names: [name for name in names if excluded(name)])
        elif source.is_symlink():
            target.symlink_to(os.readlink(source))
        else:
            shutil.copy2(source, target)
    copied = inventory(snapshot)
    if (before != copied or before != inventory(source_root)
            or before_directories != directory_inventory(snapshot)
            or before_directories != directory_inventory(source_root)):
        raise ValueError("Checkout changed while copying. Finish concurrent source edits and prepare a fresh output root.")

    removed = CASES[case_name]
    expected_module_ids = [read_module_id(snapshot, module["module_id_source"])
                           for identifier, module in spec["modules"].items() if identifier not in removed]
    expected_module_ids.append(read_module_id(snapshot, spec["local_module_id_source"]))
    remove_paths = []
    for identifier in removed:
        module = spec["modules"][identifier]
        source_files = [path for path in before if owned(path, module["source_paths"]) and path.endswith(".swift")]
        if not source_files:
            raise ValueError(f"No actual Swift code found for {identifier}; a flag-only or empty removal is invalid.")
        remove_paths.extend(module["source_paths"] + module.get("test_paths", []))
    deleted = sorted(path for path in before if owned(path, remove_paths))
    for relative in deleted:
        path = snapshot / relative
        # Never follow a symlink when deleting a module's files.
        if path.is_symlink() or path.is_file():
            path.unlink()
        else:
            raise ValueError(f"Unexpected source input type: {relative}")
    # Remove only platform-owned empty directories. Empty host directories are
    # build inputs too: a synced-folder exception may still reference them.
    for directory in sorted((path for path in snapshot.rglob("*")
                             if path.is_dir() and not path.is_symlink()
                             and owned(path.relative_to(snapshot).as_posix(), remove_paths)),
                            key=lambda path: len(path.parts), reverse=True):
        if not any(directory.iterdir()):
            directory.rmdir()

    composition_relative = spec["composition_root"]
    composition = snapshot / composition_relative
    composition.write_text(rewrite_composition(composition.read_text(), removed, spec))
    project_relative = "NeoDizzy.xcodeproj/project.pbxproj"
    project = snapshot / project_relative
    updated_project, project_exceptions = rewrite_project_membership(project.read_text(), remove_paths)
    if project_exceptions:
        project.write_text(updated_project)
    after = inventory(snapshot)
    after_directories = directory_inventory(snapshot)
    expected_directories = [path for path in before_directories if not owned(path, remove_paths)]
    if after_directories != expected_directories:
        raise ValueError("Host or survivor directory structure was modified.")
    allowed_changes = set(deleted) | {composition_relative}
    if project_exceptions:
        allowed_changes.add(project_relative)
    illegal = sorted(path for path in before.keys() | after.keys()
                     if before.get(path) != after.get(path) and path not in allowed_changes)
    if illegal:
        raise ValueError("Non-module source was modified: " + ", ".join(illegal))
    missing = sorted(path for path in deleted if path in after)
    if missing:
        raise ValueError("Module source was not physically deleted: " + ", ".join(missing))
    remaining_tests = sorted(path for path in after if path.startswith("NeoDizzyTests/") and path.endswith(".swift"))
    remaining_module_tests = {
        identifier: [path for path in remaining_tests if owned(path, module.get("test_paths", []))]
        for identifier, module in spec["modules"].items() if identifier not in removed
    }
    report = {
        "schema_version": 1, "case": case_name, "prepared_at": utc_now(),
        "source_checkout": str(source_root), "source_manifest": str(spec_path),
        "source_manifest_sha256": digest(spec_path), "ownership": spec,
        "removed_modules": list(removed),
        "remaining_modules": [name for name in spec["modules"] if name not in removed],
        "expected_module_ids": expected_module_ids,
        "removed_project_membership_exceptions": project_exceptions,
        "allowed_assembly_changes": [composition_relative] + ([project_relative] if project_exceptions else []),
        "snapshot": str(snapshot), "deleted_files": deleted,
        "deleted_product_swift_count": sum(path.startswith("NeoDizzy/") and path.endswith(".swift") for path in deleted),
        "deleted_test_swift_count": sum(path.startswith("NeoDizzyTests/") and path.endswith(".swift") for path in deleted),
        "remaining_test_files": remaining_tests,
        "remaining_module_test_files": remaining_module_tests,
        "host_and_survivor_files_unchanged": True,
        "host_and_survivor_directories_unchanged": True,
        "composition_before": (source_root / composition_relative).read_text(),
        "composition_after": composition.read_text(),
        "snapshot_before_sha256": before, "snapshot_after_sha256": after,
        "snapshot_before_directories": before_directories,
        "snapshot_after_directories": after_directories,
    }
    write_json(case_dir / "removal-manifest.json", report)
    validate_snapshot(case_dir)
    print(f"{case_name}: deleted {report['deleted_product_swift_count']} production Swift files and "
          f"{report['deleted_test_swift_count']} owned test files; retained {len(remaining_tests)} test files. "
          f"Snapshot: {snapshot}", flush=True)
    return report


def run_tests(case_dir, args):
    report = validate_snapshot(case_dir)
    artifacts = case_dir / "artifacts"
    artifacts.mkdir(exist_ok=True)
    result_bundle = artifacts / "Tests.xcresult"
    if result_bundle.exists() or (artifacts / "result.json").exists():
        raise ValueError(f"Test artifacts already exist; use a fresh snapshot for another run: {artifacts}")
    lock = artifacts / "running.lock"
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)
    source_packages = artifacts / "SourcePackages"
    derived_data = artifacts / "DerivedData"
    cache_lock = None
    result = {
        "case": report["case"], "started_at": utc_now(), "status": "running",
        "all_remaining_tests_requested": True, "destination": args.destination,
        "result_bundle": str(result_bundle), "log": str(artifacts / "xcodebuild.log"),
        "expected_module_ids": report["expected_module_ids"],
        "test_runner_environment": {
            "TEST_RUNNER_REMOVAL_EXPECTED_MODULES": ",".join(report["expected_module_ids"]),
        },
    }
    try:
        if args.reuse_build_cache:
            previous = args.reuse_build_cache / report["case"] / "artifacts"
            if previous == artifacts or not previous.is_dir():
                raise ValueError(f"Expected a separate prior artifact directory for this case: {previous}")
            if (previous / "running.lock").exists():
                raise ValueError(f"Prior case is still running; its build cache cannot be reused: {previous}")
            derived_data, source_packages = previous / "DerivedData", previous / "SourcePackages"
            if not derived_data.is_dir() or not source_packages.is_dir():
                raise ValueError(f"Prior case must contain both DerivedData and SourcePackages: {previous}")
            candidate_lock = previous / "reuse-build-cache.lock"
            descriptor = os.open(candidate_lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.close(descriptor)
            cache_lock = candidate_lock
            result["reused_build_cache_from"] = str(previous)
        elif args.seed_packages:
            if sys.platform == "darwin":
                # APFS copy-on-write clones are independent files and avoid
                # copying package checkout bytes four times. Never hard-link:
                # Xcode is allowed to mutate each private package cache.
                clone = subprocess.run(["/bin/cp", "-cR", str(args.seed_packages), str(source_packages)],
                                       capture_output=True, text=True)
                if clone.returncode != 0:
                    raise ValueError("Cannot privately clone package cache: " + clone.stderr.strip())
            else:
                shutil.copytree(args.seed_packages, source_packages, symlinks=True)
        command = [
            "xcodebuild", "test", "-project", str(case_dir / "source/NeoDizzy.xcodeproj"),
            "-scheme", "NeoDizzy", "-configuration", "Debug", "-destination", args.destination,
            "-derivedDataPath", str(derived_data),
            "-clonedSourcePackagesDirPath", str(source_packages),
            "-resultBundlePath", str(result_bundle), "-jobs", str(args.jobs),
            "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
            "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "60",
            "-onlyUsePackageVersionsFromResolvedFile",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        result["derived_data_path"] = str(derived_data)
        result["source_packages_path"] = str(source_packages)
        result["command"] = command
        write_json(artifacts / "result.json", result)
        print(f"{report['case']}: running all retained tests; log: {result['log']}", flush=True)
        started = time.monotonic()
        with (artifacts / "xcodebuild.log").open("w") as log:
            try:
                environment = os.environ.copy()
                environment.update(result["test_runner_environment"])
                process = subprocess.run(command, cwd=case_dir / "source", stdout=log,
                                         stderr=subprocess.STDOUT, timeout=args.timeout, env=environment)
                result["exit_code"] = process.returncode
                result["status"] = "passed" if process.returncode == 0 else "failed"
            except subprocess.TimeoutExpired:
                result["status"] = "timed_out"
                result["exit_code"] = 124
        result["elapsed_seconds"] = round(time.monotonic() - started, 2)
        if result_bundle.exists():
            summary = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_bundle)],
                                     text=True, capture_output=True)
            if summary.returncode == 0:
                (artifacts / "test-summary.json").write_text(summary.stdout)
                try:
                    result["test_summary"] = json.loads(summary.stdout)
                except json.JSONDecodeError:
                    result["test_summary_parse_failed"] = True
            else:
                result["summary_error"] = summary.stderr.strip()
        if result["exit_code"] == 0:
            summary = result.get("test_summary", {})
            if summary.get("totalTestCount", 0) < 1:
                result.update(status="inconclusive", exit_code=3,
                              verification_error="Xcode reported success without a readable, non-empty test result.")
            elif summary.get("failedTests", 0) > 0:
                result.update(status="failed", exit_code=1)
        environment_evidence = verify_test_environment(case_dir)
        result["actual_test_environment_verified"] = environment_evidence["verified"]
        if result["exit_code"] == 0 and not environment_evidence["verified"]:
            result.update(status="inconclusive", exit_code=3,
                          verification_error="Running Swift contract did not report the exact expected compiled module set.")
        validate_snapshot(case_dir)
        print(f"{report['case']}: {result['status']}; result: {artifacts / 'result.json'}", flush=True)
        return result["exit_code"]
    except BaseException as error:
        result.update(status="error", error=str(error))
        raise
    finally:
        result["finished_at"] = utc_now()
        write_json(artifacts / "result.json", result)
        lock.unlink(missing_ok=True)
        if cache_lock:
            cache_lock.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case", choices=(*CASES, "all"), required=True)
    parser.add_argument("--output-root", type=Path, required=True,
                        help="Must be outside the working checkout; existing case directories are never overwritten.")
    parser.add_argument("--source-root", type=Path, default=ROOT)
    parser.add_argument("--manifest", type=Path, default=ROOT / "scripts/module-removal-manifest.json")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-only", action="store_true")
    mode.add_argument("--run-prepared", action="store_true", help="Verify and test an already prepared snapshot.")
    parser.add_argument("--destination", help="Explicit Xcode simulator destination, unique per concurrent test process.")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=2400)
    parser.add_argument("--seed-packages", type=Path,
                        help="Copy an existing SourcePackages cache into each case; caches are never shared for mutation.")
    parser.add_argument("--reuse-build-cache", type=Path,
                        help="Reuse a stopped prior matrix root's per-case DerivedData and SourcePackages; results stay in the new case.")
    args = parser.parse_args()
    source_root, output_root = args.source_root.resolve(), args.output_root.resolve()
    if source_root == output_root or source_root in output_root.parents or output_root in source_root.parents:
        parser.error("Output root must be outside and must not contain the working checkout.")
    if not (source_root / "NeoDizzy.xcodeproj/project.pbxproj").is_file():
        parser.error("Source root must contain NeoDizzy.xcodeproj/project.pbxproj.")
    if not args.prepare_only and not args.destination:
        parser.error("Testing requires --destination. Use --prepare-only to capture without running Xcode.")
    if args.jobs < 1 or args.timeout < 1:
        parser.error("--jobs and --timeout must be positive.")
    if args.seed_packages:
        args.seed_packages = args.seed_packages.resolve()
        if not args.seed_packages.is_dir():
            parser.error("--seed-packages must be an existing SourcePackages directory.")
    if args.reuse_build_cache:
        args.reuse_build_cache = args.reuse_build_cache.resolve()
        if args.seed_packages:
            parser.error("Choose either --seed-packages or --reuse-build-cache.")
        if not args.reuse_build_cache.is_dir():
            parser.error("--reuse-build-cache must be an existing prior matrix output root.")
    spec_path = args.manifest.resolve()
    spec = load_spec(spec_path)
    selected = list(CASES) if args.case == "all" else [args.case]
    failed = False
    for case_name in selected:
        case_dir = output_root / case_name
        if not args.run_prepared:
            prepare(source_root, case_dir, case_name, spec, spec_path)
        if not args.prepare_only:
            failed = run_tests(case_dir, args) != 0 or failed
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"Module removal check stopped: {error}", file=sys.stderr)
        raise SystemExit(2)
