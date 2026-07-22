import Foundation
import CryptoKit

/// Backs `storage.local` (persisted, encrypted at rest) and `storage.session`
/// (in-memory, per-run) for the Tier-1 shim (FR-11, NFR-8).
///
/// `storage.local` is a JSON dictionary encrypted with AES-GCM under a key held
/// in a `0600` file in Application Support — defense in depth per Spike B, even
/// though Pass's own payloads are already encrypted. Muninn never inspects the
/// values; it only stores and returns the opaque JSON Pass hands it.
///
/// The key lived in the login Keychain, but ad-hoc dev signatures change every
/// rebuild, so the Keychain re-prompted for the password each launch (and an
/// "allow any app" ACL just traded that for an "access data from other apps"
/// prompt). A user-only file matches the accepted tradeoff (readable by any
/// process running as the user) with zero prompts (Calvin, 2026-07-22).
@MainActor
final class ExtensionStorage {
    enum Area: String { case local, session }

    private var local: [String: Any] = [:]
    private var session: [String: Any] = [:]
    private let fileURL: URL
    private let key: SymmetricKey
    private let inMemoryOnly: Bool

    /// - Parameter inMemoryOnly: tests pass true to avoid file IO.
    init(inMemoryOnly: Bool = false) {
        self.inMemoryOnly = inMemoryOnly
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Muninn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("storage.local.enc")
        self.key = inMemoryOnly ? SymmetricKey(size: .bits256) : Self.storageKey(in: dir)
        if !inMemoryOnly { self.local = loadLocal() }
    }

    // MARK: - the storage.* method surface

    /// keys may be nil (all), a String, an [String], or a { key: default } dict.
    // MARK: - Fork-gate diagnostics (ground-rule-1 safe: never logs values, only a stable
    // non-reversible tag of the key + HIT/MISS + whether stored localState is empty). Gated on
    // MUNINN_FORKGATE so normal runs write nothing.
    private static let forkGateOn = ProcessInfo.processInfo.environment["MUNINN_FORKGATE"] != nil
    private func forkTag(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined()
    }
    private func forkLog(_ msg: String) {
        guard Self.forkGateOn else { return }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Muninn/fork-gate.log")
        let line = "\(Date().ISO8601Format()) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.data(using: .utf8)?.write(to: url) }
    }
    /// Is a session key a fork-state key (`f` + a ~43-char state nonce)?
    private func isForkKey(_ k: String) -> Bool { k.hasPrefix("f") && k.count > 20 }

    func get(_ area: Area, _ keys: Any?) -> [String: Any] {
        if Self.forkGateOn, area == .session {
            func note(_ k: String) {
                guard isForkKey(k) else { return }
                let present = session[k] != nil
                let empty = (session[k] as? String).map { $0 == "{}" || $0.isEmpty } ?? false
                let stored = session.keys.filter { isForkKey($0) }.map { forkTag($0) }.joined(separator: ",")
                forkLog("consume get fork tag=\(forkTag(k)) -> \(present ? "HIT localState=\(empty ? "EMPTY" : "present")" : "MISS") | stored=[\(stored)]")
            }
            if let s = keys as? String { note(s) }
            else if let arr = keys as? [String] { arr.forEach(note) }
        }
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
            if Self.forkGateOn {
                for k in items.keys where isForkKey(k) {
                    let empty = (items[k] as? String).map { $0 == "{}" || $0.isEmpty } ?? false
                    forkLog("store fork tag=\(forkTag(k)) localState=\(empty ? "EMPTY" : "present")")
                }
            }
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

    // MARK: - storage key (0600 file, no Keychain → no prompts)

    /// The AES key, read from (or generated into) `storage.key` with user-only permissions.
    private static func storageKey(in dir: URL) -> SymmetricKey {
        let url = dir.appendingPathComponent("storage.key")
        if let data = try? Data(contentsOf: url), data.count == 32 { return SymmetricKey(data: data) }

        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        // Write owner-read/write only (0600); `.completeFileProtection` where supported.
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return fresh
    }
}
