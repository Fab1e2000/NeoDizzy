import AVFoundation
import Foundation
import Testing
@testable import NeoDizzy

nonisolated private func localTestFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

nonisolated private func localTestFile(_ path: String, in root: URL) throws -> URL {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(("test audio " + path).utf8).write(to: url)
    return url
}

private actor MetadataReads {
    var count = 0
    func read(_ url: URL) -> AudioMetadata {
        count += 1
        return AudioMetadata(title: "曲目", album: "专辑", artist: "演奏者", albumArtist: "专辑艺术家", trackNumber: 1, duration: 2)
    }
}

struct LocalLibraryTests {
    @Test @MainActor func indexRestoresImmediatelyAndRefreshRemovesDeletedFiles() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try localTestFile("Album/01.flac", in: root)
        let suite = "LocalLibrarySnapshot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reads = MetadataReads()
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { await reads.read($0) })
        let first = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        try await first.addScanFolder(root)
        #expect(first.localAlbums.count == 1)
        let restarted = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        // No await/restore needed to draw the last known library.
        #expect(restarted.localAlbums.map(\.id) == first.localAlbums.map(\.id))
        #expect(restarted.localAlbums.first?.tracks.first?.title == "曲目")
        #expect(await reads.count == 1)
        try FileManager.default.removeItem(at: file)
        await restarted.restore()
        #expect(restarted.localAlbums.isEmpty)
        #expect(OfflineLibraryStore(defaults: defaults, scanner: scanner).localAlbums.isEmpty)
    }

    @Test @MainActor func removedSourceDoesNotReturnAfterRestart() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try localTestFile("Album/01.flac", in: root)
        let suite = "LocalLibrarySnapshot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata(title: "曲目") })
        let store = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        try await store.addScanFolder(root)
        let id = try #require(store.scanFolders.first?.id)
        await store.removeScanFolder(id)
        #expect(OfflineLibraryStore(defaults: defaults, scanner: scanner).localAlbums.isEmpty)
        defaults.set(Data("invalid snapshot".utf8), forKey: "localLibrary.indexSnapshot.v1")
        #expect(OfflineLibraryStore(defaults: defaults, scanner: scanner).localAlbums.isEmpty)
    }

    @Test func targetedTagRefreshRereadsOnlyEditedFileAndPreservesIdentity() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let edited = try localTestFile("Album/01.flac", in: root)
        _ = try localTestFile("Album/02.flac", in: root)
        _ = try localTestFile("Other/03.flac", in: root)
        let reads = MetadataReads()
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { await reads.read($0) })
        let folders = [OfflineFolderAccess(url: root)]
        let before = try await scanner.scan(folders, excluding: [])
        #expect(await reads.count == 3)
        // Force rereading even if the provider preserves size and modification date.
        let after = try await scanner.scan(folders, excluding: [], refreshPaths: [LocalLibraryScanner.canonical(edited)])
        #expect(await reads.count == 4)
        #expect(before.albums.map(\.id) == after.albums.map(\.id))
        #expect(before.albums.flatMap(\.tracks).map(\.id) == after.albums.flatMap(\.tracks).map(\.id))
        _ = try await scanner.scan(folders, excluding: [])
        #expect(await reads.count == 4)
    }

    @Test func foldersStaySeparateIncludingDiscSubdirectories() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["A/CD1/01 one.flac", "A/Disc 2/01 two.flac", "B/01 another.flac", "B/01 duplicate.mp3"] {
            _ = try localTestFile(path, in: root)
        }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in
            AudioMetadata(album: "同名专辑", artist: "艺术家", albumArtist: "专辑艺术家", trackNumber: 1)
        })
        let result = try await scanner.scan([OfflineFolderAccess(url: root)], excluding: [])
        #expect(result.issues.isEmpty)
        #expect(result.albums.count == 3)
        #expect(Set(result.albums.map(\.title)) == ["CD1", "Disc 2", "B"])
        #expect(result.albums.first { $0.title == "Disc 2" }?.entries.map(\.discNumber) == [2])
        #expect(result.albums.first { $0.title == "B" }?.tracks.count == 2)
        #expect(Set(result.albums.flatMap(\.tracks).map(\.id)).count == 4)
        #expect(result.albums.allSatisfy { $0.tracks.allSatisfy { $0.discID.isEmpty && $0.localSource != nil } })
        let overlapping = try await scanner.scan([OfflineFolderAccess(url: root.appendingPathComponent("A/CD1")), OfflineFolderAccess(url: root)], excluding: [])
        #expect(Set(overlapping.albums.map(\.id)) == Set(result.albums.map(\.id)))
        #expect(overlapping.albums.flatMap(\.tracks).count == 4)
    }

    @Test func overlapExclusionHiddenFoldersAndSymlinks() async throws {
        let root = try localTestFolder()
        let outside = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let known = try localTestFile("Album/01 known.wav", in: root)
        _ = try localTestFile("Album/02 local.wav", in: root)
        _ = try localTestFile(".hidden/03 hidden.wav", in: root)
        let external = try localTestFile("external.wav", in: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.wav"), withDestinationURL: external)
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata() })
        let result = try await scanner.scan([OfflineFolderAccess(url: root), OfflineFolderAccess(url: root.appendingPathComponent("Album"))],
                                            excluding: [LocalLibraryScanner.canonical(known)])
        #expect(result.albums.count == 1)
        #expect(result.albums.first?.tracks.map(\.title) == ["local"])
        #expect(result.albums.first?.title == "Album")
    }

    @Test func cacheSurvivesRestartAndTagEditsWithoutChangingIdentity() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try localTestFile("Album/01.wav", in: root)
        let cache = root.appendingPathComponent(".cache")
        let reads = MetadataReads()
        let scanner = LocalLibraryScanner(cacheURL: cache, readMetadata: { await reads.read($0) })
        let folders = [OfflineFolderAccess(url: root)]
        let first = try await scanner.scan(folders, excluding: [])
        _ = try await scanner.scan(folders, excluding: [])
        #expect(await reads.count == 1)
        let restarted = LocalLibraryScanner(cacheURL: cache, readMetadata: { await reads.read($0) })
        let second = try await restarted.scan(folders, excluding: [])
        #expect(await reads.count == 1)
        #expect(first.albums.first?.id == second.albums.first?.id)
        try Data("modified, larger file".utf8).write(to: file)
        let edited = LocalLibraryScanner(cacheURL: cache, readMetadata: { _ in AudioMetadata(title: "新标题", album: "新专辑名", trackNumber: 7) })
        let third = try await edited.scan(folders, excluding: [])
        #expect(first.albums.first?.id == third.albums.first?.id)
        #expect(first.albums.first?.tracks.first?.id == third.albums.first?.tracks.first?.id)
        #expect(third.albums.first?.title == "Album")
        #expect(third.albums.first?.tracks.first?.title == "新标题")
    }

    @Test func damagedFileDoesNotPreventOtherAlbumsAndEmbeddedCoverWins() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try localTestFile("Album/good.wav", in: root)
        _ = try localTestFile("Album/bad.wav", in: root)
        let folderCover = try localTestFile("Album/cover.jpg", in: root)
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { url in
            if url.lastPathComponent == "bad.wav" { throw PlaybackError.unavailable }
            return AudioMetadata(artwork: Data([1, 2, 3]))
        })
        let result = try await scanner.scan([OfflineFolderAccess(url: root)], excluding: [])
        #expect(result.issues.count == 1)
        let album = try #require(result.albums.first)
        #expect(album.tracks.count == 1)
        #expect(album.coverURL != folderCover)
        #expect(try Data(contentsOf: #require(album.coverURL)) == Data([1, 2, 3]))
    }

    @Test(arguments: ["flac", "mp3", "m4a"])
    func actualAudioReadsAlbumArtistDiscAndCoverTags(format: String) async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("tagged.\(format)")
        try Fixture.data("audio-local-tags.\(format)").write(to: url)
        let metadata = try await AudioMetadataReader.read(url)
        #expect(metadata.title == "测试曲目")
        #expect(metadata.album == "测试专辑")
        #expect(metadata.artist == "曲目艺术家")
        #expect(metadata.albumArtist == "专辑艺术家")
        #expect(metadata.trackNumber == 3)
        #expect(metadata.discNumber == 2)
        #expect(metadata.artwork?.starts(with: [137, 80, 78, 71]) == true)
        #expect((metadata.duration ?? 0) > 0)
    }

    @Test func actualPCMFileAndInvalidAudioUseSystemDecoder() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("tone.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
        buffer.frameLength = 4410
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 4410)
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let metadata = try await AudioMetadataReader.read(url)
        #expect((metadata.duration ?? 0) > 0)
        let invalid = try localTestFile("invalid.flac", in: root)
        await #expect(throws: (any Error).self) { try await AudioMetadataReader.read(invalid) }
    }

    @Test func oldQueueDecodesAndLocalTracksNeverFetchSiteStreams() async throws {
        let old = Data(#"{"discID":"site","number":"1","title":"old","artists":"","albumTitle":"album"}"#.utf8)
        let site = try JSONDecoder().decode(Track.self, from: old)
        #expect(site.localSource == nil)
        #expect(site.id == "site/1")
        var local = site
        local = Track(discID: "", number: "1", title: "local", artists: "", albumTitle: "album", coverURL: nil,
                      localSource: LocalTrackSource(albumID: "album", trackID: "track"))
        #expect(try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(local)) == local)
        var requests = 0
        let resolver = StreamResolver(fetch: { _ in requests += 1; return [:] })
        for preferLocal in [true, false] {
            await #expect(throws: PlaybackError.localUnavailable) { try await resolver.stream(for: local, preferLocal: preferLocal) }
        }
        #expect(requests == 0)
    }

    @Test func directoryMigrationAndRemovalDoNotDeleteMusic() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old")
        let new = root.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        let file = try localTestFile("old.wav", in: old)
        let suite = "LocalLibraryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try old.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "offlineLibrary.folderBookmark.v1")
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata() })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        await library.restore()
        #expect(library.folderName == "old")
        #expect(library.localAlbums.count == 1)
        try await library.selectFolder(new)
        #expect(library.folderName == "new")
        #expect(library.scanFolders.count == 1)
        #expect(library.localAlbums.count == 1)
        let restored = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        await restored.restore()
        #expect(restored.scanFolders.count == 1)
        #expect(restored.localAlbums.count == 1)
        let source = try #require(restored.scanFolders.first)
        await restored.removeScanFolder(source.id)
        #expect(restored.localAlbums.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}

private actor ScanGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var resumeRead: CheckedContinuation<Void, Never>?
    func read(_ url: URL) async -> AudioMetadata {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { resumeRead = $0 }
        return AudioMetadata()
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func release() { resumeRead?.resume(); resumeRead = nil }
}

extension LocalLibraryTests {
    @Test func removingSourceSupersedesAnInFlightScan() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try localTestFile("track.wav", in: root)
        let suite = "LocalLibraryCancellation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = ScanGate()
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { await gate.read($0) })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        let adding = Task { try await library.addScanFolder(root) }
        await gate.waitUntilStarted()
        let id = try #require(library.scanFolders.first?.id)
        await library.removeScanFolder(id)
        await gate.release()
        try await adding.value
        #expect(library.localAlbums.isEmpty)
        #expect(library.scanFolders.isEmpty)
        #expect(!library.isScanning)
    }

    @Test func malformedManifestFallsBackToLocalAndRetainsIssue() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try localTestFile("Album/.neodizzy.json", in: root)
        _ = try localTestFile("Album/01.wav", in: root)
        let suite = "LocalLibraryManifest.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata() })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        try await library.addScanFolder(root)
        #expect(library.albums.isEmpty)
        #expect(library.localAlbums.count == 1)
        #expect(library.issue != nil)
    }

    @Test func corruptBookmarksLeaveReauthorizationEntryAndValidSourcesWork() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try localTestFile("song.wav", in: root)
        let suite = "LocalLibraryAuthorization.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bad = LibraryFolder(id: UUID(), name: "失效目录", bookmark: Data([0, 1]))
        let good = LibraryFolder(id: UUID(), name: "有效目录", bookmark: try root.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil))
        defaults.set(try JSONEncoder().encode([bad, good]), forKey: "localLibrary.scanFolders.v1")
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata() })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        await library.restore()
        #expect(library.scanFolders.count == 2)
        #expect(library.scanFolders.first?.issue != nil)
        #expect(library.localAlbums.count == 1)
    }
}

extension LocalLibraryTests {
    @Test func arbitrarilyRenamedDownloadFallsBackToCurrentAudioWithoutMissingFileError() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "LocalLibraryRename.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let track = Track(discID: "download", number: "1", title: "原曲名", artists: "", albumTitle: "专辑", coverURL: nil)
        let detail = DiscDetail(summary: DiscSummary(id: "download", title: "专辑", coverURL: nil), releaseDate: nil,
                                description: "", credits: "", labelDescription: "", hasGift: false, tracks: [track], streams: [:])
        let manifest = try OfflineManifest(detail: detail, files: ["1": "原曲名.flac"], coverPath: nil)
        let original = try JSONEncoder().encode(manifest)
        try original.write(to: root.appendingPathComponent(OfflineManifest.filename))
        let audio = root.appendingPathComponent("完全不同的名字.flac")
        try Fixture.data("audio-local-tags.flac").write(to: audio)
        let library = OfflineLibraryStore(defaults: defaults, scanner: LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache")))
        try await library.addScanFolder(root)
        #expect(library.issue == nil)
        #expect(library.albums.isEmpty)
        let local = try #require(library.localAlbums.first?.tracks.first)
        #expect(local.title == "测试曲目")
        let playable = try #require(library.localFile(for: local))
        #expect(LocalLibraryScanner.canonical(playable) == LocalLibraryScanner.canonical(audio))
        #expect(try Data(contentsOf: playable) == Fixture.data("audio-local-tags.flac"))
        #expect(try Data(contentsOf: root.appendingPathComponent(OfflineManifest.filename)) == original)
    }
}


extension LocalLibraryTests {
    @Test func copiedFilesStayInTheirOwnFolders() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { url in
            AudioMetadata(title: url.lastPathComponent, album: "云泠风", albumArtist: "IV015")
        })
        let six = try localTestFile("OriginalA/06.flac", in: root)
        let seven = try localTestFile("OriginalB/07.flac", in: root)
        let before = try await scanner.scan([OfflineFolderAccess(url: root)], excluding: [])
        #expect(before.albums.count == 2)
        let complete = root.appendingPathComponent("Complete")
        try FileManager.default.createDirectory(at: complete, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: six, to: complete.appendingPathComponent("06.flac"))
        try FileManager.default.copyItem(at: seven, to: complete.appendingPathComponent("07.flac"))
        _ = try localTestFile("Complete/08.flac", in: root)
        _ = try localTestFile("Different/06.flac", in: root)
        let after = try await scanner.scan([OfflineFolderAccess(url: root)], excluding: [])
        #expect(after.albums.count == 4)
        let album = try #require(after.albums.first { $0.tracks.count == 3 })
        #expect(album.title == "Complete")
        #expect(Set(before.albums.map(\.id)).isSubset(of: Set(after.albums.map(\.id))))
        #expect(after.albums.flatMap(\.tracks).count == 6)
        #expect(FileManager.default.fileExists(atPath: six.path))
        let restored = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in
            Issue.record("Unchanged metadata should be cached")
            return AudioMetadata()
        })
        let again = try await restored.scan([OfflineFolderAccess(url: root)], excluding: [])
        #expect(Set(again.albums.map(\.id)) == Set(after.albums.map(\.id)))
        #expect(again.albums.first { $0.id == album.id }?.previousIDs == album.previousIDs)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NEODIZZY_VERIFY_MUSIC_ROOT"] != nil))
    func verifiesUserMusicReadOnly() async throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["NEODIZZY_VERIFY_MUSIC_ROOT"]))
        let cache = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: cache) }
        let result = try await LocalLibraryScanner(cacheURL: cache).scan([OfflineFolderAccess(url: root)], excluding: [])
        let albums = result.albums.filter { $0.title.contains("云泠风") }
        #expect(albums.count == 1)
        #expect(albums.first?.tracks.count == 16)
        #expect(albums.first?.tracks.map(\.number) == (1...16).map(String.init))
        let yiru = try #require(result.albums.first { $0.title == "依如初见" })
        #expect(yiru.artist == "未知艺术家")
        #expect(yiru.tracks.count == 10)
        #expect(yiru.tracks.allSatisfy { $0.artists == "未知艺术家" })
    }
}


extension LocalLibraryTests {
    @Test func mixedAlbumTagsAndManagedTracksShareOneFolderAlbum() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = try localTestFile("UserAlbum/01.mp3", in: root)
        _ = try localTestFile("UserAlbum/02.mp3", in: root)
        _ = try localTestFile("UserAlbum/03.mp3", in: root)
        let site = Track(discID: "site", number: "1", title: "Downloaded", artists: "A", albumTitle: "Site title", coverURL: nil)
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { url in
            AudioMetadata(title: url.lastPathComponent, album: url.lastPathComponent, albumArtist: url.lastPathComponent)
        })
        let result = try await scanner.scan([OfflineFolderAccess(url: root)], excluding: [],
            managedTracks: [LocalLibraryScanner.canonical(managed): site])
        let album = try #require(result.albums.first)
        #expect(result.albums.count == 1)
        #expect(album.title == "UserAlbum")
        #expect(album.tracks.count == 3)
        #expect(album.tracks.first?.discID == "site")
        #expect(album.tracks.first?.title == "01.mp3")
        #expect(album.tracks.allSatisfy { $0.albumTitle == "UserAlbum" })
    }
}

extension LocalLibraryTests {
    @Test func artistAliasesPreserveMultipleCreditsAndSeparateAlbumCredits() {
        var credits = AudioArtistCredits()
        credits.add(identifier: "org.id3/TPE1", key: "TPE1", isCommonArtist: true, value: "甲\0乙")
        credits.add(identifier: "common/artist", key: "artist", isCommonArtist: true, value: "甲")
        credits.add(identifier: "", key: "ALBUM ARTIST", isCommonArtist: true, value: "社团")
        credits.add(identifier: "", key: "composer", isCommonArtist: false, value: "作曲者")
        #expect(credits.artists == ["甲", "乙"])
        #expect(credits.albumArtists == ["社团"])
    }

    @Test func meloXSidecarIsCompletelyIgnored() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("tagged.flac")
        try Fixture.data("audio-local-tags.flac").write(to: url)
        let sidecar = root.appendingPathComponent(".tagged.flac.melox.json")
        try Data(#"{"title":"错误标题","artists":["错误歌手"],"albumArtists":["错误作者"]}"#.utf8).write(to: sidecar)
        let read = try await AudioMetadataReader.read(url)
        #expect(read.title == "测试曲目")
        #expect(read.artist == "曲目艺术家")
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
    }
}

extension LocalLibraryTests {
    @Test func downloadedCopiesResolveTheirOwnFilesAndKeepIdentityWithoutManifest() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "LocalLibraryCopies.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let site = Track(discID: "download", number: "1", title: "Song", artists: "Artist", albumTitle: "Album", coverURL: nil)
        let detail = DiscDetail(summary: DiscSummary(id: "download", title: "Album", coverURL: nil), releaseDate: nil,
                                description: "", credits: "", labelDescription: "", hasGift: false, tracks: [site], streams: [:])
        let manifest = try OfflineManifest(detail: detail, files: ["1": "01.flac"], coverPath: nil)
        for folder in ["A", "B"] {
            _ = try localTestFile("\(folder)/01.flac", in: root)
            try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("\(folder)/\(OfflineManifest.filename)"))
        }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata() })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        try await library.addScanFolder(root.appendingPathComponent("A"))
        try await library.addScanFolder(root.appendingPathComponent("B"))
        let before = library.localAlbums
        #expect(before.count == 2)
        #expect(Set(before.flatMap(\.tracks).map(\.id)).count == 2)
        for album in before {
            let entry = try #require(album.entries.first)
            let resolved = try #require(library.localFile(for: entry.track))
            #expect(LocalLibraryScanner.canonical(resolved) == LocalLibraryScanner.canonical(entry.fileURL))
            #expect(library.localAlbum(for: entry.track)?.id == album.id)
        }
        #expect(library.localFile(for: site) != nil, "Site playback still finds the downloaded album")
        try FileManager.default.removeItem(at: root.appendingPathComponent("B/\(OfflineManifest.filename)"))
        await library.scan()
        #expect(before.flatMap(\.tracks).map(\.id) == library.localAlbums.flatMap(\.tracks).map(\.id))
    }
}

private actor EditableMetadataReader {
    var fails = false
    func setFailure(_ value: Bool) { fails = value }
    func read(_ url: URL) throws -> AudioMetadata {
        if fails { throw AudioTagError.message("Provider temporarily unavailable") }
        return AudioMetadata(title: "Edited title")
    }
}

extension LocalLibraryTests {
    @Test func tagRefreshDoesNotReportSuccessUsingManifestFallback() async throws {
        let root = try localTestFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "LocalLibraryRefresh.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try localTestFile("01.flac", in: root)
        let site = Track(discID: "download", number: "1", title: "Old title", artists: "Artist", albumTitle: "Album", coverURL: nil)
        let detail = DiscDetail(summary: DiscSummary(id: "download", title: "Album", coverURL: nil), releaseDate: nil,
                                description: "", credits: "", labelDescription: "", hasGift: false, tracks: [site], streams: [:])
        try JSONEncoder().encode(OfflineManifest(detail: detail, files: ["1": "01.flac"], coverPath: nil))
            .write(to: root.appendingPathComponent(OfflineManifest.filename))
        let reader = EditableMetadataReader()
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { try await reader.read($0) })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        try await library.addScanFolder(root)
        await reader.setFailure(true)
        await #expect(throws: (any Error).self) { try await library.refreshAfterTagEdit(file) }
        await reader.setFailure(false)
        let refreshed = try await library.refreshAfterTagEdit(file)
        #expect(refreshed.first { $0.id == site.id }?.title == "Edited title")
        #expect(refreshed.contains { $0.localSource != nil && $0.title == "Edited title" })
    }
}
