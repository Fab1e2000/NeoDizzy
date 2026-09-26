import Foundation

/// 开发版的诊断输出：网络失败、音频会话事件等不容易在界面上看出来的情况。
/// 同时写到 stderr 和 App 缓存目录里的 `debug.log`：
/// - 用 `xcrun devicectl device process launch --console` 启动时可以实时看到；
/// - 正常打开 App 测试后，用 `xcrun devicectl device copy from --domain-type appDataContainer` 取回文件。
/// 发布版不输出。
nonisolated func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    let time = Date.now.formatted(date: .omitted, time: .standard)
    let line = "[NeoDizzy] \(time) \(message())\n"
    FileHandle.standardError.write(Data(line.utf8))
    DebugLogFile.append(line)
#endif
}

#if DEBUG
nonisolated enum DebugLogFile {
    static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "debug.log")
    private static let queue = DispatchQueue(label: "NeoDizzy.debugLog")

    static func append(_ line: String) {
        let data = Data(line.utf8)
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
#endif
