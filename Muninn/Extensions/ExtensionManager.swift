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
        installed = loadIndex()
    }

    /// Load all enabled extensions into the controller (call once at launch).
    func loadEnabled() {
        for ext in installed where ext.enabled { loadAsync(ext) }
    }

    // MARK: install

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

    enum ExtError: Error { case noManifest }
}
