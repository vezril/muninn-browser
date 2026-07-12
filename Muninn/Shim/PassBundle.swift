import Foundation

/// Locates the embedded Proton Pass extension bundle (copied into the app's
/// Resources by the "Embed Pass Bundle" build phase from vendor/pass-extension/)
/// and exposes its root URL, canonical extension id, and parsed manifest.
enum PassBundle {
    /// The canonical production extension identity (ADR-008).
    static let canonicalID = "ghmbeldphafepmbegfdlkpapadhbakde"

    /// Custom scheme serving extension resources (ADR-006).
    static let scheme = "muninn-ext"

    /// Root of the embedded bundle, or nil if it was not embedded.
    static let rootURL: URL? = {
        Bundle.main.resourceURL?.appendingPathComponent("PassBundle", isDirectory: true)
    }()

    static var isPresent: Bool {
        guard let root = rootURL else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path)
    }

    /// The parsed manifest.json, or an empty dictionary if unreadable.
    /// Computed (not cached) to stay concurrency-safe under Swift 6 — read
    /// rarely (host start + page manifest fetch fallback).
    static var manifest: [String: Any] {
        guard let root = rootURL,
              let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    static var version: String { manifest["version"] as? String ?? "unknown" }

    /// Base URL of the extension origin, e.g. muninn-ext://<id>/
    static var originURL: URL {
        URL(string: "\(scheme)://\(canonicalID)/")!
    }
}
