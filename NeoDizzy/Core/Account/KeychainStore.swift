// 参考 NeoBili（MIT，同一作者）Core/Networking/KeychainStore.swift，改为存取 Data。

import Foundation
import Security

/// 极小的钥匙串封装，只用来保存登录凭据（会话 Cookie、token）和对应的账号信息。
nonisolated enum KeychainStore {
    private static let service = "com.elsterlee.NeoDizzy"

    struct WriteError: LocalizedError {
        let status: OSStatus
        var isDeletion = false
        var errorDescription: String? {
            let operation = isDeletion ? "清除" : "保存"
            return "无法\(operation)登录凭据（系统状态 \(status)），请重试。"
        }
    }

    /// 写入 `nil` 等价于删除该条目；任何写入失败均交由调用者处理。
    static func write(_ data: Data?, for key: String) throws {
        var query = baseQuery(for: key)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw WriteError(status: status, isDeletion: true) }
            return
        }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            #if os(iOS)
            // 锁屏后台播放时也可能要用到 token 获取播放地址。
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw WriteError(status: added) }
        } else if status != errSecSuccess { throw WriteError(status: status) }
    }

    static func data(for key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
