import SwiftUI
import UniformTypeIdentifiers

/// 批量编辑一张本地专辑里的 FLAC：只覆盖勾选的字段，逐首保存，失败不影响其他曲目。
/// 流程与 iOS 的 BatchAudioTagEditorSheet 相同。
struct BatchTagEditorSheet: View {
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
    @State private var coverFailure: String?

    private let fields = [("ARTIST", "歌手"), ("ALBUM", "专辑名"), ("ALBUMARTIST", "专辑艺术家"), ("DATE", "年份"), ("GENRE", "流派")]
    private var entries: [LocalAlbum.Entry] { album.entries.filter { $0.fileURL.pathExtension.lowercased() == "flac" } }
    private var pending: [LocalAlbum.Entry] { entries.filter { selected.contains($0.track.id) && !completed.contains($0.track.id) } }
    private var held: [LocalAlbum.Entry] { pending.filter { player.holdsFile($0.fileURL) } }
    private var dirty: Bool { !patch.fields.isEmpty || patch.replacesCover }

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView("没有 FLAC 曲目", systemImage: "music.note", description: Text("此功能仅编辑本专辑中的 FLAC 文件。"))
                    .frame(maxHeight: .infinity)
            } else {
                HSplitView {
                    trackSelection
                        .frame(minWidth: 240, idealWidth: 270)
                    changes
                        .frame(minWidth: 340)
                }
            }
            Divider()
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Text(writing ? "已保存 \(completed.count) 首" : busy ? "正在读取或刷新" : "已选择 \(selected.count) 首")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(busy ? "停止" : "关闭") {
                    if busy { cancelRequested = true }
                    else if dirty && completed.isEmpty { discardPrompt = true }
                    else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(busy && !writing)
                Button("保存") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || !dirty || pending.isEmpty || !held.isEmpty || refreshFailure != nil)
            }
            .padding(14)
        }
        .frame(width: 760, height: 560)
        .interactiveDismissDisabled(busy || dirty)
        .confirmationDialog("放弃批量编辑草稿？", isPresented: $discardPrompt) {
            Button("放弃修改", role: .destructive) { dismiss() }
        }
        .task { await load() }
    }

    private var trackSelection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(album.title).font(.headline).lineLimit(1)
                Spacer()
                Button("全选") { selected = Set(entries.filter { snapshots[$0.track.id] != nil }.map(\.track.id)) }
                Button("全不选") { selected = completed }
            }
            .buttonStyle(.link)
            .padding(12)
            .disabled(busy)
            List {
                ForEach(entries, id: \.track.id) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        if completed.contains(entry.track.id) {
                            Label(entry.track.title, systemImage: "checkmark.circle.fill").foregroundStyle(DizzyPalette.success)
                        } else {
                            Toggle(entry.track.title, isOn: selection(entry.track.id))
                                .disabled(busy || snapshots[entry.track.id] == nil)
                        }
                        if let error = failures[entry.track.id] {
                            Text(error).font(.caption).foregroundStyle(DizzyPalette.danger)
                            Button("重新读取此文件") { Task { await reload(entry) } }
                                .buttonStyle(.link).font(.caption).disabled(busy)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var changes: some View {
        Form {
            Section {
                Text("只覆盖勾选的字段；勾选后留空会删除标签。标题、曲号和碟号保持原值。")
                    .foregroundStyle(.secondary)
            }
            Section("统一修改") {
                ForEach(fields, id: \.0) { key, title in
                    Toggle(title, isOn: enabled(key))
                    if patch.fields.contains(key) {
                        if key == "ARTIST" || key == "ALBUMARTIST" {
                            NameListEditor(title: title, values: Binding(get: { patch.values.values[key] ?? [] },
                                                                         set: { patch.values.values[key] = $0 }))
                        } else {
                            TextField(title, text: Binding(get: { patch.values.text(key) }, set: { patch.values.setText(key, $0) }))
                                .labelsHidden()
                        }
                    }
                }
                Toggle("主封面", isOn: $patch.replacesCover)
                if patch.replacesCover {
                    CoverWell(data: patch.values.coverData, onChoose: chooseCover, onDrop: { try setCover($0) },
                              onRemove: { patch.values.cover = "" })
                    if patch.values.coverData == nil {
                        Text("将移除所选曲目的主封面").foregroundStyle(.secondary)
                    }
                    if let coverFailure { Text(coverFailure).foregroundStyle(DizzyPalette.danger) }
                }
            }
            .disabled(busy || !completed.isEmpty)
            if !completed.isEmpty {
                Text("已成功保存的曲目不会重复写入。若要修改其他字段，请关闭后重新打开批量编辑。")
                    .foregroundStyle(.secondary)
            }
            if !held.isEmpty {
                Section {
                    HStack {
                        Text("播放器仍持有所选文件，暂停也需要先停止才能保存。")
                        Spacer()
                        Button("停止播放") { for entry in held { player.stopForTagEditing(entry.fileURL) } }
                    }
                }
                .disabled(busy)
            }
            if let refreshFailure {
                Section {
                    Text("文件已保存，但音乐库刷新失败：\(refreshFailure)").foregroundStyle(DizzyPalette.danger)
                    Button("重试刷新") { Task { await refresh() } }.disabled(busy)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func selection(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } })
    }

    private func enabled(_ key: String) -> Binding<Bool> {
        Binding(get: { patch.fields.contains(key) }, set: { if $0 { patch.fields.insert(key) } else { patch.fields.remove(key) } })
    }

    private func chooseCover() {
        Task {
            guard let url = await FolderPanel.chooseFile(message: String(localized: "选择封面图片，会转为最大 2048 像素的 PNG。"), types: [.image]) else { return }
            do { try setCover(try CoverFile.read(url)) } catch { coverFailure = error.localizedDescription }
        }
    }

    private func setCover(_ data: Data) throws {
        guard let png = CoverImageEncoder.png(from: data) else { throw AudioTagError.message("无法读取封面图片，或图片超过 20 MB。") }
        patch.values.cover = png.base64EncodedString()
        coverFailure = nil
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
        // 写入任何文件前先锁定所有目标，避免批量写入途中开始播放其中一首。
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
}
