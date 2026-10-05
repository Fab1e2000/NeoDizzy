import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 编辑一首本地音频的内嵌标签。读取、保存与刷新流程与 iOS 的 AudioTagEditorSheet 相同；
/// 封面可从文件选择，也可直接把图片拖到封面框里。
struct TagEditorSheet: View {
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
    private var dirty: Bool { snapshot.map { $0.document != draft } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let failure {
                    Section { Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(DizzyPalette.danger) }
                }
                if saved {
                    Section {
                        Label("文件标签已保存", systemImage: "checkmark.circle")
                        Button("重试刷新音乐库") { Task { await refresh() } }.disabled(busy)
                    }
                } else if snapshot != nil {
                    Section {
                        HStack(alignment: .top, spacing: 18) {
                            CoverWell(data: draft.coverData, onChoose: chooseCover, onDrop: { try setCover($0) },
                                      onRemove: draft.cover.isEmpty ? nil : { draft.cover = "" })
                            VStack(spacing: 10) {
                                textField("标题", key: "TITLE")
                                textField("专辑名", key: "ALBUM")
                                HStack {
                                    textField("曲号", key: "TRACKNUMBER", prompt: "序号/总数")
                                    textField("碟号", key: "DISCNUMBER", prompt: "序号/总数")
                                }
                                HStack {
                                    textField("年份", key: "DATE")
                                    textField("流派", key: "GENRE")
                                }
                            }
                        }
                    }
                    Section("歌手") { names("歌手", key: "ARTIST") }
                    Section("专辑艺术家") { names("专辑艺术家", key: "ALBUMARTIST") }
                    if player.holdsFile(target.url) {
                        Section {
                            HStack {
                                Text("播放器仍持有此文件，暂停后也需要停止才能保存。")
                                Spacer()
                                Button("停止播放") { player.stopForTagEditing(target.url) }
                            }
                        }
                    }
                    Section {
                        Text("只修改当前音频的内嵌标签，不重新编码；专辑仍按文件夹归类。空白字段会删除相应标签。")
                            .foregroundStyle(.secondary)
                    }
                } else if busy {
                    ProgressView("读取文件标签").frame(maxWidth: .infinity)
                } else {
                    Button("重新读取") { Task { await load() } }
                }
            }
            .formStyle(.grouped)
            .disabled(busy)
            Divider()
            HStack {
                Text(target.url.lastPathComponent).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("重新读取") { reloadPrompt = true }
                    .disabled(busy || snapshot == nil || saved)
                Button("取消") { if dirty && !saved { discardPrompt = true } else { dismiss() } }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                Button("保存") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(snapshot == nil || !dirty || busy || saved || player.holdsFile(target.url))
            }
            .padding(14)
        }
        .frame(width: 600, height: 620)
        .interactiveDismissDisabled(dirty || busy)
        .confirmationDialog("放弃当前修改？", isPresented: $discardPrompt) {
            Button("放弃修改", role: .destructive) { dismiss() }
        }
        .confirmationDialog("重新读取会替换当前草稿", isPresented: $reloadPrompt) {
            Button("重新读取", role: .destructive) { Task { await load() } }
        }
        .task { await load() }
    }

    private func textField(_ title: String, key: String, prompt: String? = nil) -> some View {
        TextField(title, text: Binding(get: { draft.text(key) }, set: { draft.setText(key, $0) }), prompt: prompt.map { Text($0) })
    }

    private func names(_ title: String, key: String) -> some View {
        NameListEditor(title: title, values: Binding(get: { draft.values[key] ?? [] }, set: { draft.values[key] = $0 }))
    }

    private func chooseCover() {
        Task {
            guard let url = await FolderPanel.chooseFile(message: String(localized: "选择封面图片，会转为最大 2048 像素的 PNG。"), types: [.image]) else { return }
            do { try setCover(try CoverFile.read(url)) } catch { failure = error.localizedDescription }
        }
    }

    private func setCover(_ data: Data) throws {
        guard let png = CoverImageEncoder.png(from: data), png.count <= CoverImageEncoder.maximumBytes else {
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
        } catch { failure = String(localized: "文件已保存，但音乐库刷新失败：\(error.localizedDescription)") }
    }
}

/// 多人姓名逐个填写，不按 `/` 拆分。
struct NameListEditor: View {
    let title: String
    @Binding var values: [String]

    var body: some View {
        ForEach(values.indices, id: \.self) { index in
            HStack {
                TextField(title, text: Binding(get: { values.indices.contains(index) ? values[index] : "" },
                                               set: { if values.indices.contains(index) { values[index] = $0 } }))
                    .labelsHidden()
                    .accessibilityLabel("\(title)第 \(index + 1) 项")
                Button { values.remove(at: index) } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("移除\(title)第 \(index + 1) 项")
            }
        }
        Button("添加\(title)", systemImage: "plus") { values.append("") }
            .buttonStyle(.borderless)
    }
}

/// 封面框：显示当前内嵌封面，点击选择文件，或把图片拖进来。
struct CoverWell: View {
    let data: Data?
    let onChoose: () -> Void
    let onDrop: (Data) throws -> Void
    var onRemove: (() -> Void)?
    @State private var isTargeted = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onChoose) {
                ZStack {
                    if let data, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus").font(.title2)
                            Text("无封面").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isTargeted ? Color.dizzyAccent : .primary.opacity(0.1),
                                                                         lineWidth: isTargeted ? 3 : 1))
            }
            .buttonStyle(.plain)
            .help("点击选择图片，或把图片拖到这里")
            .dropDestination(for: Data.self) { items, _ in
                guard let item = items.first else { return false }
                do { try onDrop(item); failure = nil; return true } catch { failure = error.localizedDescription; return false }
            } isTargeted: { isTargeted = $0 }
            HStack(spacing: 10) {
                Button("选择…", action: onChoose).buttonStyle(.link)
                if let onRemove { Button("移除", role: .destructive, action: onRemove).buttonStyle(.link) }
            }
            .font(.callout)
            if let failure { Text(failure).font(.caption).foregroundStyle(DizzyPalette.danger).frame(width: 150) }
        }
    }
}

enum CoverFile {
    /// 读取用户选择的封面文件，超过 20 MB 的不读入内存。
    static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= CoverImageEncoder.maximumBytes else {
            throw AudioTagError.message("封面不能超过 20 MB。")
        }
        return try Data(contentsOf: url)
    }
}
