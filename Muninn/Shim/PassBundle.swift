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

    /// Exact hosts from the manifest's `externally_connectable.matches` (e.g.
    /// `account.proton.me`, `pass.proton.me`) — the ONLY origins on which the page
    /// MAIN world may receive the narrow `chrome.runtime` externally_connectable
    /// bridge (E6). Derived from the manifest so it stays in parity with the vendored
    /// bundle; Chrome match-pattern host semantics are an exact host match.
    static var externallyConnectableHosts: [String] {
        guard let ec = manifest["externally_connectable"] as? [String: Any],
              let matches = ec["matches"] as? [String] else { return [] }
        return matches.compactMap { pattern in
            // "https://account.proton.me/*" → host "account.proton.me"
            URL(string: pattern.replacingOccurrences(of: "/*", with: "/"))?.host?.lowercased()
        }
    }

    /// Base URL of the extension origin, e.g. muninn-ext://<id>/
    static var originURL: URL {
        URL(string: "\(scheme)://\(canonicalID)/")!
    }
}
