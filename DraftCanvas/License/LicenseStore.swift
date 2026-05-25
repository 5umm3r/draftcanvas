import Foundation
import Security

final class LicenseStore: @unchecked Sendable {
    static let shared = LicenseStore()
    private let service = Bundle.main.bundleIdentifier ?? "com.spade3.DraftCanvas"
    private let formatter = ISO8601DateFormatter()
    private let defaults = UserDefaults.standard

    private init() {}

    var licenseKey: String? {
        get { readKeychainString(account: "licenseKey") }
        set {
            if let v = newValue { writeKeychainString(v, account: "licenseKey") }
            else { deleteItem(account: "licenseKey") }
        }
    }

    // 実体は Polar の activation_id
    var instanceID: String? {
        get { readKeychainString(account: "instanceID") }
        set { if let v = newValue { writeKeychainString(v, account: "instanceID") } }
    }

    var trialStartDate: Date? {
        get { readDefaultsDate(key: "trialStartDate") }
        set { if let v = newValue { defaults.set(formatter.string(from: v), forKey: "trialStartDate") } }
    }

    private var lastSeenDate: Date? {
        get { readDefaultsDate(key: "lastSeenDate") }
        set { if let v = newValue { defaults.set(formatter.string(from: v), forKey: "lastSeenDate") } }
    }

    func loadOrInitTrial() -> Date {
        if let d = trialStartDate { return d }
        let now = Date()
        trialStartDate = now
        return now
    }

    func detectClockRollback() -> Bool {
        let now = Date()
        if let last = lastSeenDate, now < last - 60 { return true }
        lastSeenDate = now
        return false
    }

    private func readDefaultsDate(key: String) -> Date? {
        guard let s = defaults.string(forKey: key) else { return nil }
        return formatter.date(from: s)
    }

    private func readKeychainString(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func resetAll() {
        deleteItem(account: "licenseKey")
        deleteItem(account: "instanceID")
        defaults.removeObject(forKey: "trialStartDate")
        defaults.removeObject(forKey: "lastSeenDate")
    }

    func deleteItem(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func writeKeychainString(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
