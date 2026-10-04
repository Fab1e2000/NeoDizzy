import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct BatchAudioTagEditorSheet: View {
    let album: LocalAlbum
    @Environment(\.dismiss) private var dismiss
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @State private var patch = AudioTagBatchPatch()
    @State private var selected: Set<String> = []
    @State private var snapshots: [String: AudioTagSnapshot] = [:]
    @State private var accesses: [String: OfflineFolderAccess] = [:]
    @State private var failures: [String: String] = [:]
    @State private var completed: Set<String> = []
    @State private var busy = false
    @State private var writing = false
    @State private var cancelRequested = false
    @State private var discardPrompt = false
    @State private var refreshFailure: String?
    @State private var photo: PhotosPickerItem?
    @State private var importsCover = false
    @State private var coverFailure: String?
    @State private var loadingCover = false
    @State private var coverTask: Task<Void, Never>?

    private let fields = [("ARTIST", "歌手"), ("ALBUM", "专辑名"), ("ALBUMARTIST", "专辑艺术家"), ("DATE", "年份"), ("GENRE", "流派")]
    private var entries: [LocalAlbum.Entry] { album.entries.filter { $0.fileURL.pathExtension.lowercased() == "flac" } }
    private var pending: [LocalAlbum.Entry] { entries.filter { selected.contains($0.track.id) && !completed.contains($0.track.id) } }
    private var held: [LocalAlbum.Entry] { pending.filter { player.holdsFile($0.fileURL) } }
    private var dirty: Bool { !patch.fields.isEmpty || patch.replacesCover }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(album.title).font(.headline)
                    Text("只覆盖勾选的字段；勾选后留空会删除标签。每首文件单独保存，失败不影响其他曲目。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if busy { ProgressView(writing ? "已保存 \(completed.count) 首" : "正在读取或刷新") }
                }
                if entries.isEmpty {
                    ContentUnavailableView("没有 FLAC 曲目", systemImage: "music.note", description: Text("此功能仅编辑本专辑中的 FLAC 文件。"))
                } else {
                    Section("曲目 · 已选择 \(selected.count) 首") {
                        HStack {
                            Button("全选") { selected = Set(entries.filter { snapshots[$0.track.id] != nil }.map(\.track.id)) }
                            Spacer()
                            Button("取消全选") { selected = completed }
                        }.disabled(busy)
                        ForEach(entries, id: \.track.id) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                if completed.contains(entry.track.id) {
                                    Label(entry.track.title, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                                } else {
                                    Toggle(entry.track.title, isOn: selection(entry.track.id))
                                        .disabled(busy || snapshots[entry.track.id] == nil)
                                }
                                if let error = failures[entry.track.id] {
                                    Text(error).font(.caption).foregroundStyle(.red)
                                    Button("重新读取此文件") { Task { await reload(entry) } }.disabled(busy)
                                }
                            }
                        }
                    }
                    Section("统一修改") {
                        ForEach(fields, id: \.0) { key, title in
                            Toggle(title, isOn: enabled(key))
                            if patch.fields.contains(key) {
                                if key == "ARTIST" || key == "ALBUMARTIST" {
                                    names(key, title: title)
                                } else {
                                    TextField(title, text: Binding(get: { patch.values.text(key) }, set: { patch.values.setText(key, $0) }))
                                }
                            }
                        }
                        Toggle("主封面", isOn: $patch.replacesCover)
                        if patch.replacesCover {
                            if let data = patch.values.coverData, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                            } else { Text("将移除所选曲目的主封面").foregroundStyle(.secondary) }
                            PhotosPicker("从照片选择", selection: $photo, matching: .images)
                            Button("从文件选择") { importsCover = true }
                            Button("移除主封面", role: .destructive) { patch.values.cover = "" }
                            if loadingCover { ProgressView("读取封面") }
                            if let coverFailure { Text(coverFailure).foregroundStyle(.red) }
                        }
                    }.disabled(busy || !completed.isEmpty || loadingCover)
                    if !completed.isEmpty {
                        Text("已成功保存的曲目不会重复写入。若要修改其他字段，请关闭后重新打开批量编辑。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !held.isEmpty {
                        Section {
                            Text("播放器仍持有所选文件，暂停也需要先停止才能保存。")
                            Button("停止播放以保存") { for entry in held { player.stopForTagEditing(entry.fileURL) } }
                        }.disabled(busy)
                    }
                    if let refreshFailure {
                        Section {
                            Text("文件已保存，但音乐库刷新失败：\(refreshFailure)").foregroundStyle(.red)
                            Button("重试刷新") { Task { await refresh() } }.disabled(busy)
                        }
                    }
                }
            }
            .safeAreaPadding(.top, 5)
            .navigationTitle("批量编辑 FLAC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(busy ? "停止" : "关闭") {
                        if busy { cancelRequested = true }
                        else if dirty && completed.isEmpty { discardPrompt = true }
                        else { dismiss() }
                    }.disabled(busy && !writing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(busy || loadingCover || !dirty || pending.isEmpty || !held.isEmpty || refreshFailure != nil)
                }
            }
            .interactiveDismissDisabled(busy || dirty)
            .confirmationDialog("放弃批量编辑草稿？", isPresented: $discardPrompt, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
            }
            .task { await load() }
            .onDisappear { coverTask?.cancel() }
            .onChange(of: photo) { _, selection in
                coverTask?.cancel()
                loadingCover = true
                coverTask = Task {
                    defer { if !Task.isCancelled { loadingCover = false } }
                    do {
                        if let data = try await selection?.loadTransferable(type: Data.self) {
                            try Task.checkCancellation()
                            try setCover(data)
                        }
                    } catch { if !Task.isCancelled { coverFailure = error.localizedDescription } }
                }
            }
            .fileImporter(isPresented: $importsCover, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 20 * 1024 * 1024 else {
                        throw AudioTagError.message("封面不能超过 20 MB。")
                    }
                    try setCover(Data(contentsOf: url))
                } catch { coverFailure = error.localizedDescription }
            }
        }
    }

    private func selection(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } })
    }
    private func enabled(_ key: String) -> Binding<Bool> {
        Binding(get: { patch.fields.contains(key) }, set: { if $0 { patch.fields.insert(key) } else { patch.fields.remove(key) } })
    }
    private func names(_ key: String, title: String) -> some View {
        VStack {
            ForEach(Array((patch.values.values[key] ?? []).indices), id: \.self) { index in
                HStack {
                    TextField(title, text: Binding(get: {
                        let values = patch.values.values[key] ?? []
                        return values.indices.contains(index) ? values[index] : ""
                    }, set: { value in
                        guard patch.values.values[key]?.indices.contains(index) == true else { return }
                        patch.values.values[key]?[index] = value
                    }))
                    Button("移除", systemImage: "minus.circle", role: .destructive) { patch.values.values[key]?.remove(at: index) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            Button("添加\(title)") { patch.values.values[key, default: []].append("") }
        }
    }
    private func load() async {
        busy = true
        defer { busy = false }
        for entry in entries {
            if Task.isCancelled { return }
            await read(entry)
            if snapshots[entry.track.id] != nil { selected.insert(entry.track.id) }
        }
        for (key, _) in fields {
            let values = snapshots.values.map { $0.document.values[key] ?? [] }
            if let first = values.first, values.allSatisfy({ $0 == first }) { patch.values.values[key] = first }
        }
    }
    private func read(_ entry: LocalAlbum.Entry) async {
        do {
            guard let access = library.access(for: entry.track) else { throw PlaybackError.localUnavailable }
            let snapshot = try await AudioTagEditor.shared.read(entry.fileURL, access: access, flacOnly: true)
            snapshots[entry.track.id] = snapshot
            accesses[entry.track.id] = access
            failures[entry.track.id] = nil
        } catch { failures[entry.track.id] = error.localizedDescription; snapshots[entry.track.id] = nil }
    }
    private func reload(_ entry: LocalAlbum.Entry) async {
        busy = true
        defer { busy = false }
        await read(entry)
    }
    private func save() async {
        let targets = pending
        busy = true
        writing = true
        cancelRequested = false
        defer { busy = false; writing = false }
        var locks: [URL] = []
        defer { for url in locks { player.endTagWrite(url) } }
        // Reserve every target before writing any file, preventing a mid-batch playback race.
        for entry in targets {
            do { try player.beginTagWrite(entry.fileURL); locks.append(entry.fileURL) }
            catch { failures[entry.track.id] = error.localizedDescription; return }
        }
        for entry in targets {
            if cancelRequested || Task.isCancelled { break }
            do {
                guard let snapshot = snapshots[entry.track.id], let access = accesses[entry.track.id] else {
                    throw AudioTagError.message("请先重新读取文件标签。")
                }
                let draft = try patch.applying(to: snapshot.document)
                try await library.saveTags(draft, snapshot: snapshot, url: entry.fileURL, access: access)
                completed.insert(entry.track.id)
                failures[entry.track.id] = nil
            } catch { failures[entry.track.id] = error.localizedDescription }
        }
        writing = false
        if !completed.isEmpty { await refresh() }
    }
    private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            let urls = entries.filter { completed.contains($0.track.id) }.map(\.fileURL)
            let tracks = try await library.refreshAfterTagEdits(urls)
            player.refreshMetadata(tracks)
            refreshFailure = nil
            if pending.isEmpty && !cancelRequested {
                try await Task.sleep(for: .milliseconds(500))
                dismiss()
            }
        } catch is CancellationError { return }
        catch { refreshFailure = error.localizedDescription }
    }
    private func setCover(_ data: Data) throws {
        guard let png = CoverImageEncoder.png(from: data) else { throw AudioTagError.message("无法读取封面图片，或图片超过 20 MB。") }
        patch.values.cover = png.base64EncodedString()
        coverFailure = nil
    }
}
