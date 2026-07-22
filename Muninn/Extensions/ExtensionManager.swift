import WebKit

/// A record of an installed web extension (its unpacked folder + enabled state), persisted.
struct InstalledExtension: Codable, Identifiable {
    var id: String            // stable folder name / unique id
    var name: String
    var folderPath: String    // absolute path to the unpacked extension (containing manifest.json)
    var enabled: Bool
}

/// Loads and runs Web Extensions via Apple's `WKWebExtension` API (macOS 15.4+). Extensions are
/// unpacked into Application Support; the shared `WKWebExtensionController` is attached to every
/// tab's configuration so extension content scripts / background / actions run.
@MainActor
final class ExtensionManager {
    static let shared = ExtensionManager()

    let controller = WKWebExtensionController(configuration: .default())
    private(set) var installed: [InstalledExtension] = []
    private var contexts: [String: WKWebExtensionContext] = [:]   // id → loaded context
    var onChange: (() -> Void)?

    /// True once any extension is enabled — the signal to attach the controller to new tabs.
    /// (Attaching the controller injects a `browser` global into every page's MAIN world, so we
    /// keep it off entirely until the user opts in, preserving the Pass shim's clean-world S2.)
    var hasEnabledExtensions: Bool { installed.contains { $0.enabled } }

    /// Loaded contexts (for the extensions toolbar — action icons/popups). Reads the controller's
    /// own set so it can't desync from our bookkeeping.
    var loadedContexts: [WKWebExtensionContext] { Array(controller.extensionContexts) }
    func context(for id: String) -> WKWebExtensionContext? { contexts[id] }

    private let dir: URL
    private let indexURL: URL

    private init() {
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory).appendingPathComponent("Muninn", isDirectory: true)
        dir = base.appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        indexURL = dir.appendingPathComponent("index.json")
        // Stay hermetic under XCTest: don't load the developer's real installed extensions (an
        // attached controller would leak `browser` into the MAIN world and break the S2 tests).
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        installed = underTest ? [] : loadIndex()
    }

    /// Load all enabled extensions into the controller (call once at launch).
    func loadEnabled() {
        for ext in installed where ext.enabled { loadAsync(ext) }
    }

    // MARK: install

    /// Install directly from the Chrome Web Store, given a store URL or a bare 32-char extension id.
    /// Downloads the CRX from Google's update endpoint, strips the CRX header to a plain ZIP, and
    /// runs it through the normal unpack/load path.
    func addFromWebStore(_ input: String) async throws {
        guard let id = Self.extensionID(from: input) else { throw ExtError.badStoreURL }
        // Google's on-demand CRX endpoint (follows a redirect to the actual file).
        let endpoint = "https://clients2.google.com/service/update2/crx?response=redirect"
            + "&acceptformat=crx2,crx3&prodversion=130.0.0.0"
            + "&x=id%3D\(id)%26installsource%3Dondemand%26uc"
        guard let url = URL(string: endpoint) else { throw ExtError.badStoreURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 16 else {
            throw ExtError.downloadFailed
        }
        // Strip the CRX header → clean ZIP, write to a temp file, unpack under the extension id.
        let zip = Self.zipData(fromCRX: data)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).zip")
        try? FileManager.default.removeItem(at: tmp)
        try zip.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await add(from: tmp)
    }

    /// Extract a 32-char (a–p) Chrome extension id from a store URL or a bare id.
    static func extensionID(from input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: "^[a-p]{32}$", options: .regularExpression) != nil { return s }
        if let r = s.range(of: "[a-p]{32}", options: .regularExpression) { return String(s[r]) }
        return nil
    }

    /// Return the ZIP payload inside a CRX (v2/v3), or the data unchanged if it isn't a CRX.
    static func zipData(fromCRX data: Data) -> Data {
        guard data.count > 16, data.prefix(4) == Data("Cr24".utf8) else { return data }
        func u32(_ offset: Int) -> Int {
            Int(data[data.startIndex + offset]) | (Int(data[data.startIndex + offset + 1]) << 8)
                | (Int(data[data.startIndex + offset + 2]) << 16) | (Int(data[data.startIndex + offset + 3]) << 24)
        }
        let version = u32(4)
        let zipStart: Int
        if version == 3 {
            zipStart = 12 + u32(8)                    // magic+version+headerLen, then header
        } else if version == 2 {
            zipStart = 16 + u32(8) + u32(12)          // magic+version+pubkeyLen+sigLen, then pubkey+sig
        } else {
            return data
        }
        guard zipStart < data.count else { return data }
        return data.subdata(in: (data.startIndex + zipStart)..<data.endIndex)
    }

    /// Add an extension from an unpacked folder or a .zip/.crx archive.
    func add(from url: URL) async throws {
        let folder: URL
        if url.hasDirectoryPath {
            folder = try copyIntoPlace(url)
        } else {
            folder = try unpackArchive(url)
        }
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) else {
            throw ExtError.noManifest
        }
        let webExt = try await WKWebExtension(resourceBaseURL: folder)
        let name = webExt.displayName ?? folder.lastPathComponent
        let record = InstalledExtension(id: folder.lastPathComponent, name: name, folderPath: folder.path, enabled: true)
        installed.removeAll { $0.id == record.id }
        installed.append(record)
        saveIndex()
        load(webExt, id: record.id)   // we already have the loaded WKWebExtension
        onChange?()
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard let i = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[i].enabled = enabled
        if enabled { loadAsync(installed[i]) } else { unloadContext(id) }
        saveIndex(); onChange?()
    }

    func remove(_ id: String) {
        unloadContext(id)
        if let ext = installed.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(atPath: ext.folderPath)
        }
        installed.removeAll { $0.id == id }
        saveIndex(); onChange?()
    }

    // MARK: loading

    /// Re-create the WKWebExtension from disk (async), then load it into the controller.
    private func loadAsync(_ ext: InstalledExtension) {
        guard contexts[ext.id] == nil else { return }
        let id = ext.id, name = ext.name, path = ext.folderPath
        Task { @MainActor in
            do {
                let webExt = try await WKWebExtension(resourceBaseURL: URL(fileURLWithPath: path))
                load(webExt, id: id)
            } catch {
                NSLog("[ext] load failed for %@: %@", name, String(describing: error))
            }
        }
    }

    /// Load an already-created WKWebExtension into the controller (context + grant + load).
    private func load(_ webExt: WKWebExtension, id: String) {
        guard contexts[id] == nil else { return }
        let context = WKWebExtensionContext(for: webExt)
        grantAll(context)
        do {
            try controller.load(context)
            contexts[id] = context
            context.isInspectable = true   // allow attaching Web Inspector to an extension's popup/background
            onChange?()   // context is live now (loads are async) → refresh the action toolbar
        } catch {
            NSLog("[ext] controller.load failed for %@: %@", id, String(describing: error))
        }
    }

    private func unloadContext(_ id: String) {
        guard let context = contexts[id] else { return }
        try? controller.unload(context)
        contexts[id] = nil
    }

    /// Grant the extension its requested permissions + host access (MVP: auto-grant). Uses
    /// `allRequestedMatchPatterns` (which includes content-script `matches`, not just
    /// `host_permissions`) so declared content scripts actually get host access and inject.
    private func grantAll(_ context: WKWebExtensionContext) {
        for perm in context.webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: perm)
        }
        for pattern in context.webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
    }

    // MARK: files

    private func copyIntoPlace(_ src: URL) throws -> URL {
        let dest = dir.appendingPathComponent(src.lastPathComponent, isDirectory: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    private func unpackArchive(_ archive: URL) throws -> URL {
        let dest = dir.appendingPathComponent(archive.deletingPathExtension().lastPathComponent, isDirectory: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        // unzip handles .zip and (via the trailing central directory) most .crx files.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", "-q", archive.path, "-d", dest.path]
        try p.run(); p.waitUntilExit()
        // If the manifest is nested one level down, use that folder.
        if !FileManager.default.fileExists(atPath: dest.appendingPathComponent("manifest.json").path),
           let sub = try? FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
            .first(where: { $0.hasDirectoryPath && FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }) {
            return sub
        }
        return dest
    }

    private func loadIndex() -> [InstalledExtension] {
        (try? JSONDecoder().decode([InstalledExtension].self, from: Data(contentsOf: indexURL))) ?? []
    }
    private func saveIndex() {
        if let data = try? JSONEncoder().encode(installed) { try? data.write(to: indexURL, options: .atomic) }
    }


    enum ExtError: LocalizedError {
        case noManifest, badStoreURL, downloadFailed
        var errorDescription: String? {
            switch self {
            case .noManifest:   return "No manifest.json found in the extension."
            case .badStoreURL:   return "Couldn't find an extension id in that URL. Paste a Chrome Web Store link or the 32-character id."
            case .downloadFailed: return "The download failed. Check the link and your connection."
            }
        }
    }
}
