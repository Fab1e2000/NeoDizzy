#!/usr/bin/env python3
"""在 macOS 上测试真实 Foundation 核心源文件；不替代 iOS 设备和 UI 测试。"""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PINS = ROOT / "NeoDizzy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def main():
    if sys.platform != "darwin":
        raise SystemExit("此脚本需要 macOS 和 Xcode 27 的 Swift 工具链。")
    pins = {pin["identity"]: pin for pin in json.loads(PINS.read_text())["pins"]}
    dependencies = ['.package(path: "' + str(ROOT / "Packages/AudioTags") + '")']
    for name in ("swiftsoup", "zipfoundation"):
        pin = pins[name]
        dependencies.append(
            f'.package(url: "{pin["location"]}", exact: "{pin["state"]["version"]}")'
        )

    with tempfile.TemporaryDirectory(prefix="neodizzy-core-tests-") as temporary:
        package = Path(temporary)
        sources = package / "Sources/NeoDizzy"
        tests = package / "Tests/NeoDizzyTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        files = []
        for directory in ("Models", "TagEditing", "Lyrics", "Networking", "OfflineLibrary", "Downloads", "Purchases", "Community"):
            files.extend((ROOT / "NeoDizzy/Core" / directory).rglob("*.swift"))
        files.extend(ROOT / "NeoDizzy/Core" / name for name in (
            "BrowsingHistory/BrowsingHistoryStore.swift", "DebugLog.swift", "UI/PagedList.swift", "Account/DizzyAuth.swift", "Playback/PlaybackQueue.swift",
            "Playback/PlaybackPersistence.swift", "Playback/StreamResolver.swift",
        ))
        for source in files:
            shutil.copy2(source, sources / source.name)
        for name in (
            "AudioTagEditingTests", "LocalLyricsTests", "LocalLibraryTests", "PlaybackTests", "DownloadTests", "OfflineLibraryTests", "JSONDecodingTests",
            "PageParserTests", "DizzyURLTests", "AccountTests", "PurchaseTests",
            "PurchaseConfirmationTests", "CheckoutNavigationTests", "PurchaseStoreTests",
            "AlipayReturnRouterTests", "CommunityTests", "FeedPaginationTests", "BrowsingHistoryTests",
        ):
            shutil.copy2(ROOT / f"NeoDizzyTests/{name}.swift", tests / f"{name}.swift")
        # Xcode test bundles use Bundle(for:); SwiftPM puts resources in Bundle.module.
        fixture = (ROOT / "NeoDizzyTests/Fixture.swift").read_text()
        assert "Bundle(for: BundleToken.self)" in fixture
        (tests / "Fixture.swift").write_text(fixture.replace("Bundle(for: BundleToken.self)", "Bundle.module"))
        shutil.copytree(ROOT / "NeoDizzyTests/Fixtures", tests / "Fixtures")
        settings = """[.swiftLanguageMode(.v5), .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("DisableOutwardActorInference"),
            .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableUpcomingFeature("InferSendableFromCaptures"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("MemberImportVisibility")]"""
        (package / "Package.swift").write_text(f"""// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "NeoDizzyCoreChecks", platforms: [.macOS(.v15)],
    dependencies: [{', '.join(dependencies)}],
    targets: [
        .target(name: "NeoDizzy", dependencies: ["SwiftSoup", "ZIPFoundation", .product(name: "AudioTagBridge", package: "AudioTags")], swiftSettings: {settings}),
        .testTarget(name: "NeoDizzyTests", dependencies: ["NeoDizzy"],
            resources: [.copy("Fixtures")], swiftSettings: {settings})
    ]
)
""")
        print("测试核心解析、下载、离线目录与队列逻辑；iOS 后台唤醒、文件授权和播放仍需设备验收。", flush=True)
        result = subprocess.run(["xcrun", "swift", "test", "--package-path", str(package), *sys.argv[1:]], cwd=ROOT)
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
