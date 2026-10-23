#!/usr/bin/env python3
"""Scan every iOS host file and every module for concrete cross-boundary types.

Only AppComposition may name module implementations, to register them. The
physical-removal matrix additionally checks extension members and compilation.
"""
from pathlib import Path
import re
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
MODULE_NAMES = ("DizzyLab", "Netease", "QQMusic")
MODULE_ROOTS = {name: (f"NeoDizzy/Core/Modules/{name}", f"NeoDizzy/Features/Modules/{name}")
                for name in MODULE_NAMES}
COMPOSITION = "NeoDizzy/App/Modules/AppComposition.swift"
DECLARATION = re.compile(r"\b(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_]\w*)")


def module_owner(relative):
    return next((name for name, roots in MODULE_ROOTS.items()
                 if any(relative.startswith(root + "/") for root in roots)), None)


def code_only(source):
    """Mask comments/string literals while keeping line numbers intact."""
    chars = list(source)
    cursor = 0
    while cursor < len(source):
        start = cursor
        if source.startswith("//", cursor):
            end = source.find("\n", cursor)
            cursor = len(source) if end == -1 else end
        elif source.startswith("/*", cursor):
            cursor += 2
            depth = 1
            while cursor < len(source) and depth:
                if source.startswith("/*", cursor):
                    depth += 1
                    cursor += 2
                elif source.startswith("*/", cursor):
                    depth -= 1
                    cursor += 2
                else:
                    cursor += 1
        else:
            string = re.match(r'(#+)?("""|")', source[cursor:])
            if not string:
                cursor += 1
                continue
            hashes, quote = string.group(1) or "", string.group(2)
            cursor += len(string.group())
            terminator = quote + hashes
            while cursor < len(source):
                if source.startswith(terminator, cursor):
                    cursor += len(terminator)
                    break
                if not hashes and source[cursor] == "\\":
                    cursor += 2
                else:
                    cursor += 1
        for index in range(start, min(cursor, len(chars))):
            if chars[index] != "\n":
                chars[index] = " "
    return "".join(chars)


def main():
    sources = {path.relative_to(ROOT).as_posix(): code_only(path.read_text())
               for path in (ROOT / "NeoDizzy").rglob("*.swift")}
    host_types = set()
    owned_types = {name: set() for name in MODULE_NAMES}
    for relative, source in sources.items():
        types = set()
        for match in DECLARATION.finditer(source):
            prefix = source[:match.start()]
            # Nested/private helpers are scoped to a declaration/file, not exported contracts.
            line_prefix = prefix.rsplit("\n", 1)[-1]
            if prefix.count("{") == prefix.count("}") and "private" not in line_prefix:
                types.add(match.group(1))
        owner = module_owner(relative)
        if owner:
            owned_types[owner].update(types)
        else:
            host_types.update(DECLARATION.findall(source))
    # Private helper names reused by unrelated files are not platform contracts.
    unique_types = {name: types - host_types - set().union(*(owned_types[other]
                    for other in MODULE_NAMES if other != name))
                    for name, types in owned_types.items()}
    failures = []
    checked = 0
    for relative, source in sources.items():
        if relative == COMPOSITION:
            continue
        owner = module_owner(relative)
        forbidden = set().union(*(types for name, types in unique_types.items() if name != owner))
        for match in re.finditer(r"\b[A-Za-z_]\w*\b", source):
            if match.group() in forbidden:
                line = source.count("\n", 0, match.start()) + 1
                failures.append(f"{relative}:{line}: concrete cross-module dependency {match.group()}")
        checked += 1
    # Test fixtures must obey the same ownership rules. Multi-platform integration
    # tests list every required module in the physical-removal manifest.
    manifest = json.loads((ROOT / "scripts/module-removal-manifest.json").read_text())
    test_count = 0
    for path in (ROOT / "NeoDizzyTests").rglob("*.swift"):
        relative = path.relative_to(ROOT).as_posix()
        source = code_only(path.read_text())
        allowed = set()
        for name in MODULE_NAMES:
            if relative.startswith(f"NeoDizzyTests/Modules/{name}/"):
                allowed.add(name)
            paths = manifest["modules"][name.lower()]["test_paths"]
            if relative.startswith("NeoDizzyTests/Modules/Integration/") and relative in paths:
                allowed.add(name)
        local_types = set(DECLARATION.findall(source))
        forbidden = set().union(*(types for name, types in unique_types.items() if name not in allowed)) - local_types
        for match in re.finditer(r"\b[A-Za-z_]\w*\b", source):
            if match.group() in forbidden:
                line = source.count("\n", 0, match.start()) + 1
                failures.append(f"{relative}:{line}: test depends on unowned module type {match.group()}")
        test_count += 1
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    host_count = sum(module_owner(path) is None for path in sources)
    print(f"Module boundaries passed: {checked} Swift files scanned ({host_count} host files); "
          f"plus {test_count} test files; no unowned concrete platform dependencies outside composition.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
