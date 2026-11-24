import Foundation
import Security

/// Wi-Fi 암호는 UserDefaults가 아닌 로그인 키체인에 저장한다.
enum Keychain {
    private static func query(_ ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "NetKeeper",
         kSecAttrAccount as String: ssid]
    }

    static func set(_ password: String, for ssid: String) {
        SecItemDelete(query(ssid) as CFDictionary)
        guard !password.isEmpty else { return }
        var item = query(ssid)
        item[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func password(for ssid: String) -> String? {
        var q = query(ssid)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
