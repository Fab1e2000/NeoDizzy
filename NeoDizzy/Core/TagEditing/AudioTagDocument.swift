import Foundation
import AudioTagBridge

nonisolated struct AudioTagDocument: Codable, Equatable, Sendable {
    var values: [String: [String]]
    var cover: String
    static let keys = ["TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "TRACKNUMBER", "DISCNUMBER", "DATE", "GENRE"]
    func text(_ key: String) -> String { values[key]?.first ?? "" }
    var coverData: Data? { cover.isEmpty ? nil : Data(base64Encoded: cover) }

    mutating func setText(_ key: String, _ text: String) { values[key] = text.isEmpty ? [] : [text] }
    func validated(preserving original: Self) throws -> Self {
        var result = self
        for key in Self.keys where values[key] != original.values[key] {
            let list = (values[key] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard list.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 16_384 }) else { throw AudioTagError.message("标签文字过长或含有无效字符。") }
            result.values[key] = list
        }
        for key in ["TRACKNUMBER", "DISCNUMBER"] where values[key] != original.values[key] {
            let text = result.text(key)
            if !text.isEmpty {
                let parts = text.split(separator: "/", omittingEmptySubsequences: false)
                guard (1...2).contains(parts.count), parts.allSatisfy({ Int($0).map { $0 > 0 && $0 <= 999_999 } == true }) else {
                    throw AudioTagError.message("曲号和碟号请填写正整数，或“序号/总数”。")
                }
            }
        }
        return result
    }
}

nonisolated enum AudioTagError: LocalizedError {
    case message(String)
    case conflict
    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .conflict: "文件已被修改、移动或替换。请重新读取标签后再保存；当前草稿仍保留。"
        }
    }
}

nonisolated enum AudioTagCodec {
    static func read(_ url: URL, flacOnly: Bool = false) throws -> AudioTagDocument {
        let data = try response(NDTagRead(url.path))
        if flacOnly, (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["isFLAC"] as? Bool != true {
            throw AudioTagError.message("批量编辑仅支持实际容器为 FLAC 的文件。")
        }
        return try JSONDecoder().decode(AudioTagDocument.self, from: data)
    }
    static func write(_ document: AudioTagDocument, original: AudioTagDocument, to url: URL) throws {
        let edited = try document.validated(preserving: original)
        let year = edited.text("DATE")
        if year != original.text("DATE"), !year.isEmpty,
           !(year.count == 4 && Int(year).map { (1...9999).contains($0) } == true) {
            throw AudioTagError.message("年份请填写四位数字。")
        }
        var changed: [String: [String]] = [:]
        for key in AudioTagDocument.keys where edited.values[key] != original.values[key] { changed[key] = edited.values[key] ?? [] }
        let action = edited.cover == original.cover ? "keep" : edited.cover.isEmpty ? "remove" : "replace"
        let png = edited.coverData?.starts(with: [137, 80, 78, 71]) == true
        let json = try JSONSerialization.data(withJSONObject: ["values": changed, "coverAction": action, "cover": edited.cover, "mime": png ? "image/png" : "image/jpeg"])
        _ = try response(NDTagWrite(url.path, String(decoding: json, as: UTF8.self)))
        let saved = try read(url)
        for (key, values) in changed where saved.values[key] != values {
            throw AudioTagError.message("写入后的标签验证失败（\(key)），原文件未更改。")
        }
        if action == "replace", saved.cover != edited.cover { throw AudioTagError.message("封面验证失败，原文件未更改。") }
    }
    private static func response(_ pointer: UnsafeMutablePointer<CChar>?) throws -> Data {
        guard let pointer else { throw AudioTagError.message("标签服务没有返回结果。") }
        defer { NDTagFree(pointer) }
        let data = Data(String(cString: pointer).utf8)
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let message = object["error"] as? String {
            throw AudioTagError.message(message)
        }
        return data
    }
}

/// Only explicitly enabled fields participate; an enabled empty value removes a tag.
nonisolated struct AudioTagBatchPatch {
    var fields: Set<String> = []
    var values = AudioTagDocument(values: [:], cover: "")
    var replacesCover = false

    func applying(to original: AudioTagDocument) throws -> AudioTagDocument {
        var result = original
        for key in AudioTagDocument.keys where fields.contains(key) {
            result.values[key] = values.values[key] ?? []
        }
        if replacesCover { result.cover = values.cover }
        return try result.validated(preserving: original)
    }
}
