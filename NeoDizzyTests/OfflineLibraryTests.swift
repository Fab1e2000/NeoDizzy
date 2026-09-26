import Foundation
import Testing
@testable import NeoDizzy

nonisolated private func offlineTrack(_ number: String, title: String) -> Track {
    Track(discID: "album1", number: number, title: title, artists: "演奏者", albumTitle: "测试专辑", coverURL: nil, duration: 120)
}

nonisolated private func offlineDetail(tracks: [Track]) -> DiscDetail {
    DiscDetail(summary: DiscSummary(id: "album1", title: "测试专辑", coverURL: nil, labelName: "测试社团"),
               releaseDate: "2026-09-26", description: "离线介绍", credits: "制作名单", labelDescription: "社团介绍",
               hasGift: false, tracks: tracks, streams: ["1": URL(string: "https://example.com/private-signed-stream")!])
}

nonisolated private func temporaryOfflineDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

nonisolated private func writeOfflineFile(_ path: String, in root: URL) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: url)
}

struct AudioFileMatcherTests {
    @Test func matchesChineseTitlesAndNestedNumberedFilesWithoutDependingOnOrder() throws {
        let tracks = [offlineTrack("1", title: "第一首"), offlineTrack("2", title: "夜空、繁星"), offlineTrack("10", title: "终曲")]
        let files = ["专辑/10 - 终曲.FLAC", "专辑/02. 夜空、繁星.flac", "专辑/01 第一首.flac"]
        let result = try AudioFileMatcher.match(tracks: tracks, relativePaths: files)
        #expect(result["1"] == "专辑/01 第一首.flac")
        #expect(result["2"] == "专辑/02. 夜空、繁星.flac")
        #expect(result["10"] == "专辑/10 - 终曲.FLAC")
    }

    @Test func matchesTitlesWithoutNumbersAndUnicodeEquivalentNames() throws {
        let tracks = [offlineTrack("1", title: "星の海"), offlineTrack("2", title: "Café")]
        let result = try AudioFileMatcher.match(tracks: tracks, relativePaths: ["Cafe\u{301}.wav", "星の海.mp3"])
        #expect(result["1"] == "星の海.mp3")
        #expect(result["2"] == "Cafe\u{301}.wav")
    }

    @Test func supportsFullWidthAndTrackPrefixes() throws {
        let tracks = [offlineTrack("1", title: "序曲"), offlineTrack("2", title: "终曲")]
        let result = try AudioFileMatcher.match(tracks: tracks, relativePaths: ["０１．序曲.wav", "Track 02 - 终曲.wav"])
        #expect(result.count == 2)
    }

    @Test func numericSongTitlesRemainTitles() throws {
        let result = try AudioFileMatcher.match(tracks: [offlineTrack("1", title: "1984")], relativePaths: ["1984.mp3"])
        #expect(result["1"] == "1984.mp3")
    }

    @Test func acceptsExplicitBareTrackNumbers() throws {
        let result = try AudioFileMatcher.match(tracks: [offlineTrack("2", title: "曲目")], relativePaths: ["02.wav"])
        #expect(result["2"] == "02.wav")
    }

    @Test func neverAssignsAlphabeticalFilesByPosition() {
        #expect(throws: OfflineLibraryError.missingTrack("第一首")) {
            try AudioFileMatcher.match(tracks: [offlineTrack("1", title: "第一首"), offlineTrack("2", title: "第二首")], relativePaths: ["A.mp3", "B.mp3"])
        }
    }

    @Test func rejectsMissingTrack() {
        #expect(throws: OfflineLibraryError.missingTrack("第二首")) {
            try AudioFileMatcher.match(tracks: [offlineTrack("1", title: "第一首"), offlineTrack("2", title: "第二首")], relativePaths: ["01 第一首.flac"])
        }
    }

    @Test func rejectsMultipleFormatsAndDuplicateNumbers() {
        for files in [["01 曲目.wav", "01 曲目.mp3"], ["CD1/01 曲目.wav", "CD2/01 其他曲目.wav"]] {
            #expect(throws: OfflineLibraryError.ambiguousTrack("曲目")) {
                try AudioFileMatcher.match(tracks: [offlineTrack("1", title: "曲目")], relativePaths: files)
            }
        }
    }

    @Test func rejectsConflictingTrackNumberAndKnownTitle() {
        #expect(throws: OfflineLibraryError.ambiguousTrack("第一首")) {
            try AudioFileMatcher.match(tracks: [offlineTrack("1", title: "第一首"), offlineTrack("2", title: "第二首")], relativePaths: ["01 第二首.wav", "02 第一首.wav"])
        }
    }

    @Test func oneFileCannotServeTwoIdenticallyNamedTracks() {
        #expect(throws: OfflineLibraryError.ambiguousTrack("同名")) {
            try AudioFileMatcher.match(tracks: [offlineTrack("1", title: "同名"), offlineTrack("2", title: "同名")], relativePaths: ["同名.wav"])
        }
    }
}

struct OfflineManifestTests {
    @Test func importWritesManifestAndRestoresCompleteOfflineDetail() throws {
        let source = try temporaryOfflineDirectory()
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: root) }
        try writeOfflineFile("原始目录/01 星空.flac", in: source)
        try writeOfflineFile("原始目录/cover.jpg", in: source)
        let detail = offlineDetail(tracks: [offlineTrack("1", title: "星空")])

        let committed = try OfflineLibraryWorker.importDirectory(from: source, detail: detail, into: root)
        #expect(committed.id == detail.id)
        #expect(committed.localFile(for: detail.tracks[0]) != nil)
        let scan = try OfflineLibraryWorker.scanDirectory(root)
        let album = try #require(scan.albums.first)
        #expect(committed.directoryURL.standardizedFileURL.resolvingSymlinksInPath().path == album.directoryURL.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(scan.issues.isEmpty)
        #expect(album.directoryURL.lastPathComponent == "测试专辑 [album1]")
        #expect(album.directoryURL.deletingLastPathComponent().lastPathComponent == "测试社团")
        #expect(album.id == detail.id)
        #expect(album.tracks.map(\.title) == ["星空"])
        #expect(album.detail.description == "离线介绍")
        #expect(album.detail.credits == "制作名单")
        #expect(album.detail.streams.isEmpty)
        #expect(album.coverURL?.isFileURL == true)
        #expect(album.localFile(for: detail.tracks[0])?.lastPathComponent == "01 星空.flac")
        let manifestData = try Data(contentsOf: album.directoryURL.appendingPathComponent(OfflineManifest.filename))
        let json = String(decoding: manifestData, as: UTF8.self)
        #expect(!json.contains("private-signed-stream"))
        #expect(!json.contains(source.path))
        let decoded = try JSONDecoder().decode(OfflineManifest.self, from: manifestData)
        #expect(decoded.version == 1)
        #expect(decoded.entries[0].relativePath == "原始目录/01 星空.flac")
    }

    @Test func refusesOverwriteAndKeepsExistingAlbumIntact() throws {
        let source = try temporaryOfflineDirectory()
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: root) }
        try writeOfflineFile("01.wav", in: source)
        let detail = offlineDetail(tracks: [offlineTrack("1", title: "星空")])
        try OfflineLibraryWorker.importDirectory(from: source, detail: detail, into: root)
        #expect(throws: OfflineLibraryError.existingAlbum) {
            try OfflineLibraryWorker.importDirectory(from: source, detail: detail, into: root)
        }
        #expect(try OfflineLibraryWorker.scanDirectory(root).albums.count == 1)
    }

    @Test func failedMatchingDoesNotLeavePartialAlbum() throws {
        let source = try temporaryOfflineDirectory()
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: root) }
        try writeOfflineFile("unmatched.wav", in: source)
        #expect(throws: OfflineLibraryError.missingTrack("星空")) {
            try OfflineLibraryWorker.importDirectory(from: source, detail: offlineDetail(tracks: [offlineTrack("1", title: "星空")]), into: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func rejectsTraversalAndAbsolutePaths() throws {
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["../secret.wav", "/tmp/secret.wav", "music/../../secret.wav", "music//track.wav", "music/./track.wav", "music\\secret.wav", "", "\0.wav"] {
            #expect(throws: OfflineLibraryError.unsafePath(path)) { try OfflinePaths.file(path, inside: root) }
        }
        #expect(try OfflinePaths.file("专辑/01. 歌曲.wav", inside: root).path.hasPrefix(root.path))
    }

    @Test func rejectsSymlinkEscapeDuringManifestValidationAndImport() throws {
        let source = try temporaryOfflineDirectory()
        let external = try temporaryOfflineDirectory()
        let root = try temporaryOfflineDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: external)
            try? FileManager.default.removeItem(at: root)
        }
        try writeOfflineFile("01.wav", in: external)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape"), withDestinationURL: external)
        #expect(throws: OfflineLibraryError.unsafePath("escape/01.wav")) {
            try OfflinePaths.file("escape/01.wav", inside: source)
        }
        #expect(throws: OfflineLibraryError.unsafePath("escape")) {
            try OfflineLibraryWorker.importDirectory(from: source, detail: offlineDetail(tracks: [offlineTrack("1", title: "星空")]), into: root)
        }
    }

    @Test func relativePathsAcceptSystemAliasesAndDirectoryTrailingSlash() throws {
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOfflineFile("专辑/01.wav", in: root)
        let canonicalFile = root.appendingPathComponent("专辑/01.wav").resolvingSymlinksInPath()
        let directoryRoot = URL(fileURLWithPath: root.path, isDirectory: true)
        #expect(try OfflinePaths.relativePath(of: canonicalFile, inside: directoryRoot) == "专辑/01.wav")
        #expect(try OfflinePaths.relativePath(of: root.appendingPathComponent("专辑/01.wav"), inside: root.resolvingSymlinksInPath()) == "专辑/01.wav")
    }

    @Test func rootAliasAllowsMissingDescendantsAndPreservesSelectedURL() throws {
        let container = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("实际音乐目录", isDirectory: true)
        let alias = container.appendingPathComponent("所选目录", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)

        let path = "新社团/新专辑/01 星空.flac"
        let destination = try OfflinePaths.file(path, inside: alias)
        #expect(destination.path == alias.appendingPathComponent(path).path)
        #expect(try OfflinePaths.relativePath(of: destination, inside: alias) == path)
        try writeOfflineFile(path, in: alias)
        #expect(try Data(contentsOf: OfflinePaths.file(path, inside: alias)) == Data("fixture".utf8))
        #expect(try OfflinePaths.relativePath(of: root.appendingPathComponent(path), inside: alias) == path)
    }

    @Test func rejectsSymlinkEscapeBeforeMissingDescendants() throws {
        let container = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("音乐", isDirectory: true)
        let alias = container.appendingPathComponent("所选目录", isDirectory: true)
        let outside = container.appendingPathComponent("外部", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)

        for selectedRoot in [root, alias] {
            for path in ["escape/01.wav", "escape/新目录/01.wav"] {
                #expect(throws: OfflineLibraryError.unsafePath(path)) {
                    try OfflinePaths.file(path, inside: selectedRoot)
                }
                #expect(throws: OfflineLibraryError.unsafePath(path)) {
                    try OfflinePaths.relativePath(of: selectedRoot.appendingPathComponent(path), inside: selectedRoot)
                }
            }
        }
    }

    @Test func rejectsDanglingSymlinkAndItsMissingDescendants() throws {
        let container = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("音乐", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dangling"),
                                                 withDestinationURL: container.appendingPathComponent("不存在"))
        for path in ["dangling", "dangling/01.wav", "dangling/新目录/01.wav"] {
            #expect(throws: OfflineLibraryError.unsafePath(path)) {
                try OfflinePaths.file(path, inside: root)
            }
        }
    }

    @Test func importsAndPlaysAlbumThroughSelectedRootAlias() throws {
        let source = try temporaryOfflineDirectory()
        let container = try temporaryOfflineDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: container)
        }
        let realParent = container.appendingPathComponent("实际路径", isDirectory: true)
        let aliasParent = container.appendingPathComponent("系统别名", isDirectory: true)
        let root = realParent.appendingPathComponent("音乐", isDirectory: true)
        let alias = aliasParent.appendingPathComponent("音乐", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasParent, withDestinationURL: realParent)
        try writeOfflineFile("原始目录/01 星空.flac", in: source)
        let detail = offlineDetail(tracks: [offlineTrack("1", title: "星空")])

        let album = try OfflineLibraryWorker.importDirectory(from: source, detail: detail, into: alias)
        let localFile = try #require(album.localFile(for: detail.tracks[0]))
        #expect(localFile.path.hasPrefix(alias.path + "/"))
        #expect(try Data(contentsOf: localFile) == Data("fixture".utf8))
        let scan = try OfflineLibraryWorker.scanDirectory(alias)
        #expect(scan.issues.isEmpty)
        #expect(scan.albums.map(\.id) == [detail.id])
        #expect(scan.albums.first?.localFile(for: detail.tracks[0]) != nil)
    }

    @Test func missingAudioSkipsAlbumWithIssue() throws {
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try OfflineManifest(detail: offlineDetail(tracks: [offlineTrack("1", title: "星空")]), files: ["1": "missing.wav"], coverPath: nil)
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent(OfflineManifest.filename))
        let scan = try OfflineLibraryWorker.scanDirectory(root)
        #expect(scan.albums.isEmpty)
        #expect(scan.issues.count == 1)
    }

    @Test func rejectsFutureManifestVersionAndDuplicateTrackFiles() throws {
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOfflineFile("01.wav", in: root)
        let detail = offlineDetail(tracks: [offlineTrack("1", title: "星空")])
        let manifest = try OfflineManifest(detail: detail, files: ["1": "01.wav"], coverPath: nil)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
        json["version"] = 999
        let future = try JSONDecoder().decode(OfflineManifest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: OfflineLibraryError.invalidManifest) { try future.validate(in: root) }

        let duplicated = try OfflineManifest(detail: offlineDetail(tracks: [offlineTrack("1", title: "一"), offlineTrack("2", title: "二")]), files: ["1": "01.wav", "2": "01.wav"], coverPath: nil)
        #expect(throws: OfflineLibraryError.invalidManifest) { try duplicated.validate(in: root) }
    }

    @Test func traversalInsideManifestIsNotPlayable() throws {
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = offlineDetail(tracks: [offlineTrack("1", title: "星空")])
        let manifest = try OfflineManifest(detail: detail, files: ["1": "../01.wav"], coverPath: nil)
        #expect(throws: OfflineLibraryError.unsafePath("../01.wav")) { try manifest.validate(in: root) }
        #expect(OfflineAlbum(manifest: manifest, directoryURL: root).localFile(for: detail.tracks[0]) == nil)
    }

    @Test func safeNamesCannotCreateExtraDirectoriesAndFitFilesystemLimit() {
        let value = OfflinePaths.directoryName("社团/名字\\：" + String(repeating: "很长", count: 100), fallback: "未知")
        #expect(!value.contains("/"))
        #expect(!value.contains("\\"))
        #expect(value.utf8.count <= 100)
        #expect(OfflinePaths.directoryName("..", fallback: "未知") == "未知")
        let commonPrefix = String(repeating: "长曲名", count: 80)
        let firstID = OfflinePaths.identifierName(commonPrefix + "一")
        let secondID = OfflinePaths.identifierName(commonPrefix + "二")
        #expect(firstID != secondID)
        #expect("\(value) [\(firstID)]".utf8.count < 255)
    }

    @Test func duplicateDiscIDsAreNotChosenByEnumerationOrder() throws {
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try OfflineManifest(detail: offlineDetail(tracks: [offlineTrack("1", title: "星空")]), files: ["1": "01.wav"], coverPath: nil)
        for name in ["A", "B"] {
            let album = root.appendingPathComponent(name)
            try writeOfflineFile("01.wav", in: album)
            try JSONEncoder().encode(manifest).write(to: album.appendingPathComponent(OfflineManifest.filename))
        }
        let scan = try OfflineLibraryWorker.scanDirectory(root)
        #expect(scan.albums.isEmpty)
        #expect(scan.issues.count == 1)
    }

    @Test func cancelledImportDoesNotCommit() async throws {
        let source = try temporaryOfflineDirectory()
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: root) }
        try writeOfflineFile("01.wav", in: source)
        let task = Task {
            try OfflineLibraryWorker.importDirectory(from: source, detail: offlineDetail(tracks: [offlineTrack("1", title: "星空")]), into: root)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func cancellationAfterCommitKeepsReturnedAlbumPlayable() async throws {
        let source = try temporaryOfflineDirectory()
        let root = try temporaryOfflineDirectory()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: root) }
        try writeOfflineFile("01.wav", in: source)
        let detail = offlineDetail(tracks: [offlineTrack("1", title: "星空")])
        let worker = OfflineLibraryWorker()
        let folder = OfflineFolderAccess(url: root)
        let task = Task {
            let committed = try await worker.importAlbum(from: source, detail: detail, into: folder)
            // 模拟提交完成、调用方恢复执行时恰好收到取消。
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(Task.isCancelled)
            return committed
        }
        let committed = try await task.value
        #expect(committed.id == detail.id)
        #expect(committed.localFile(for: detail.tracks[0]) != nil)
        #expect(FileManager.default.fileExists(atPath: committed.directoryURL.appendingPathComponent(OfflineManifest.filename).path))
        #expect(try OfflineLibraryWorker.scanDirectory(root).albums.map(\.id) == [detail.id])
    }
}

@MainActor
struct OfflineLibraryStoreTests {
    @Test func selectedFolderBookmarkRestoresLibraryInNewStore() async throws {
        let source = try temporaryOfflineDirectory()
        let root = try temporaryOfflineDirectory()
        let suite = "NeoDizzyTests.Offline.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: root)
        }
        try writeOfflineFile("01.wav", in: source)
        let detail = offlineDetail(tracks: [offlineTrack("1", title: "星空")])
        let original = OfflineLibraryStore(defaults: defaults)
        try await original.selectFolder(root)
        try await original.importAlbum(from: source, detail: detail)
        #expect(original.albums.count == 1)
        #expect(original.localFile(for: detail.tracks[0]) != nil)
        #expect(!original.isScanning)

        let restored = OfflineLibraryStore(defaults: defaults)
        await restored.restore()
        #expect(restored.folderName == root.lastPathComponent)
        #expect(restored.albums.map(\.id) == ["album1"])
        #expect(restored.localFile(for: detail.tracks[0]) != nil)
        #expect(restored.issue == nil)
    }
}
