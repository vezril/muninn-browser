import Foundation
import CryptoKit

/// Backs `storage.local` (persisted, encrypted at rest) and `storage.session`
/// (in-memory, per-run) for the Tier-1 shim (FR-11, NFR-8).
///
/// `storage.local` is a JSON dictionary encrypted with AES-GCM under a key held
/// in the Keychain — defense in depth per Spike B, even though Pass's own
/// payloads are already encrypted. Muninn never inspects the values; it only
/// stores and returns the opaque JSON Pass hands it.
@MainActor
final class ExtensionStorage {
    enum Area: String { case local, session }

    private var local: [String: Any] = [:]
    private var session: [String: Any] = [:]
    private let fileURL: URL
    private let key: SymmetricKey
    private let inMemoryOnly: Bool

    /// - Parameter inMemoryOnly: tests pass true to avoid Keychain/file IO.
    init(inMemoryOnly: Bool = false) {
        self.inMemoryOnly = inMemoryOnly
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Muninn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("storage.local.enc")
        self.key = inMemoryOnly ? SymmetricKey(size: .bits256) : Self.keychainKey()
        if !inMemoryOnly { self.local = loadLocal() }
    }

    // MARK: - the storage.* method surface

    /// keys may be nil (all), a String, an [String], or a { key: default } dict.
    func get(_ area: Area, _ keys: Any?) -> [String: Any] {
        let store = area == .local ? local : session
        switch keys {
        case nil, is NSNull:
            return store
        case let s as String:
            return store[s].map { [s: $0] } ?? [:]
        case let arr as [String]:
            var out: [String: Any] = [:]
            for k in arr where store[k] != nil { out[k] = store[k] }
            return out
        case let defaults as [String: Any]:
            var out = defaults
            for (k, _) in defaults where store[k] != nil { out[k] = store[k]! }
            return out
        default:
            return [:]
        }
    }

    func set(_ area: Area, _ items: [String: Any]) {
        if area == .local {
            for (k, v) in items { local[k] = v }
            persistLocal()
        } else {
            for (k, v) in items { session[k] = v }
        }
    }

    func remove(_ area: Area, _ keys: Any?) {
        let list: [String]
        switch keys {
        case let s as String: list = [s]
        case let a as [String]: list = a
        default: list = []
        }
        if area == .local {
            for k in list { local.removeValue(forKey: k) }
            persistLocal()
        } else {
            for k in list { session.removeValue(forKey: k) }
        }
    }

    func clear(_ area: Area) {
        if area == .local { local.removeAll(); persistLocal() } else { session.removeAll() }
    }

    // MARK: - encrypted persistence

    private func loadLocal() -> [String: Any] {
        guard let blob = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key),
              let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any]
        else { return [:] }
        return obj
    }

    private func persistLocal() {
        guard !inMemoryOnly else { return }
        guard let plain = try? JSONSerialization.data(withJSONObject: local),
              let sealed = try? AES.GCM.seal(plain, using: key).combined
        else { return }
        try? sealed.write(to: fileURL, options: .atomic)
    }

    // MARK: - Keychain key

    private static let keychainAccount = "com.vezril.Muninn.extension-storage-key"

    private static func keychainKey() -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainAccount,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
            return SymmetricKey(data: data)
        }
        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(add as CFDictionary, nil)
        return fresh
    }
}
