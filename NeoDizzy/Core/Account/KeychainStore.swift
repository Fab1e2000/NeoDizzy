// 参考 NeoBili（MIT，同一作者）Core/Networking/KeychainStore.swift，改为存取 Data。

import Foundation
import Security

/// 极小的钥匙串封装，只用来保存登录凭据（会话 Cookie、token）和对应的账号信息。
nonisolated enum KeychainStore {
    private static let service = "com.elsterlee.NeoDizzy"

    /// 写入 `nil` 等价于删除该条目。
    static func set(_ data: Data?, for key: String) {
        var query = baseQuery(for: key)
        guard let data else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            // 锁屏后台播放时也可能要用到 token 获取播放地址。
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
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
