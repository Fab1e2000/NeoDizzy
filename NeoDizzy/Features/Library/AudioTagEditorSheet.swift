import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct AudioTagEditTarget: Identifiable {
    let track: Track
    let url: URL
    var id: String { url.path }
}

struct AudioTagEditorSheet: View {
    let target: AudioTagEditTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @State private var snapshot: AudioTagSnapshot?
    @State private var draft = AudioTagDocument(values: [:], cover: "")
    @State private var access: OfflineFolderAccess?
    @State private var failure: String?
    @State private var busy = false
    @State private var saved = false
    @State private var reloadPrompt = false
    @State private var discardPrompt = false
    @State private var photo: PhotosPickerItem?
    @State private var importsCover = false
    @State private var coverTask: Task<Void, Never>?
    @State private var loadingCover = false
    private var dirty: Bool { snapshot.map { $0.document != draft } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                if let failure {
                    Section { Text(failure).foregroundStyle(.red) }
                }
                if saved {
                    Section {
                        Label("文件标签已保存", systemImage: "checkmark.circle")
                        Button("重试刷新音乐库") { Task { await refresh() } }.disabled(busy)
                    }
                } else if snapshot != nil {
                    Section("音乐标签") {
                        textField("标题", key: "TITLE")
                        names("歌手", key: "ARTIST")
                        textField("专辑名", key: "ALBUM")
                        names("专辑艺术家", key: "ALBUMARTIST")
                        textField("曲号（可填序号/总数）", key: "TRACKNUMBER")
                        textField("碟号（可填序号/总数）", key: "DISCNUMBER")
                        textField("年份", key: "DATE")
                        textField("流派", key: "GENRE")
                    }
                    .disabled(busy)
                    Section("内嵌主封面") {
                        if let data = draft.coverData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                        } else { Text("无内嵌封面").foregroundStyle(.secondary) }
                        PhotosPicker("从照片选择", selection: $photo, matching: .images)
                        Button("从文件选择") { importsCover = true }
                        if !draft.cover.isEmpty { Button("移除主封面", role: .destructive) { draft.cover = "" } }
                        if loadingCover { ProgressView("正在读取封面") }
                    }
                    .disabled(busy || loadingCover)
                    if player.holdsFile(target.url) {
                        Section {
                            Text("播放器仍持有此文件，暂停后也需要停止才能保存。")
                            Button("停止播放以保存") { player.stopForTagEditing(target.url) }
                        }
                    }
                    Section {
                        Button("重新读取文件标签") { reloadPrompt = true }.disabled(busy)
                    } footer: {
                        Text("只修改当前音频的内嵌标签；专辑仍按文件夹归类。空白字段会删除相应标签。")
                    }
                } else if busy { ProgressView("读取文件标签") }
                else { Button("重新读取") { Task { await load() } } }
            }
            .navigationTitle("编辑音乐标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if dirty && !saved { discardPrompt = true } else { dismiss() } }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(snapshot == nil || !dirty || busy || loadingCover || saved || player.holdsFile(target.url))
                }
            }
            .interactiveDismissDisabled(dirty || busy)
            .confirmationDialog("放弃当前修改？", isPresented: $discardPrompt, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
            }
            .confirmationDialog("重新读取会替换当前草稿", isPresented: $reloadPrompt, titleVisibility: .visible) {
                Button("重新读取", role: .destructive) { Task { await load() } }
            }
            .fileImporter(isPresented: $importsCover, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 20 * 1024 * 1024 else { throw AudioTagError.message("封面不能超过 20 MB。") }
                        try setCover(Data(contentsOf: url))
                    } catch { failure = error.localizedDescription }
                } else if case .failure(let error) = result { failure = error.localizedDescription }
            }
            .onChange(of: photo) { _, selection in
                coverTask?.cancel()
                loadingCover = selection != nil
                coverTask = Task {
                    defer { if !Task.isCancelled { loadingCover = false } }
                    do {
                        if let data = try await selection?.loadTransferable(type: Data.self) {
                            try Task.checkCancellation()
                            try setCover(data)
                        }
                    } catch { if !Task.isCancelled { failure = error.localizedDescription } }
                }
            }
            .task { await load() }
            .onDisappear { coverTask?.cancel() }
        }
    }

    private func textField(_ title: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: Binding(get: { draft.text(key) }, set: { draft.setText(key, $0) }))
                .accessibilityLabel(title)
        }
    }
    private func names(_ title: String, key: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(Array((draft.values[key] ?? []).indices), id: \.self) { index in
                HStack {
                    TextField(title, text: Binding(get: { draft.values[key]?[safe: index] ?? "" }, set: { value in
                        guard draft.values[key]?.indices.contains(index) == true else { return }
                        draft.values[key]?[index] = value
                    }))
                    .accessibilityLabel("\(title)第 \(index + 1) 项")
                    Button(role: .destructive) { draft.values[key]?.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).accessibilityLabel("移除\(title)第 \(index + 1) 项")
                }
            }
            Button("添加\(title)") { draft.values[key, default: []].append("") }.buttonStyle(.borderless)
        }
    }
    private func setCover(_ data: Data) throws {
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary),
              let png = UIImage(cgImage: thumbnail).pngData(), png.count <= 20 * 1024 * 1024 else {
            throw AudioTagError.message("封面必须是可读取的图片，且不能超过 20 MB。")
        }
        draft.cover = png.base64EncodedString()
    }
    private func load() async {
        busy = true
        failure = nil
        defer { busy = false }
        do {
            guard let access = library.access(for: target.track) else { throw PlaybackError.localUnavailable }
            self.access = access
            let result = try await AudioTagEditor.shared.read(target.url, access: access)
            try Task.checkCancellation()
            snapshot = result
            draft = result.document
        } catch { failure = error.localizedDescription }
    }
    private func save() async {
        guard let snapshot, let access else { return }
        busy = true
        failure = nil
        defer { busy = false }
        do {
            try player.beginTagWrite(target.url)
            defer { player.endTagWrite(target.url) }
            try await library.saveTags(draft, snapshot: snapshot, url: target.url, access: access)
            saved = true
            await refresh()
        } catch { failure = error.localizedDescription }
    }
    private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            let tracks = try await library.refreshAfterTagEdit(target.url)
            player.refreshMetadata(tracks)
            try await Task.sleep(for: .milliseconds(500))
            dismiss()
        } catch is CancellationError {
            return
        } catch { failure = "文件已保存，但音乐库刷新失败：\(error.localizedDescription)" }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
