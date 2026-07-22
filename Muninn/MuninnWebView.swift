import WebKit

/// The app's `WKWebView` subclass. In Developer Mode it adds **View Page Source** and
/// **Inspect Element** to the right-click menu, the latter opening the real WebKit Web
/// Inspector in-app.
///
/// ⚠️ The in-app inspector uses a **private** WebKit API (`WKWebView._inspector` → `-show`).
/// It is reached only from Developer Mode (off by default), so the private path is dormant
/// unless the user opts in. Should the private symbol ever disappear, `showInspector()` fails
/// closed (no crash) and the public `isInspectable` + Safari Develop-menu route still works.
final class MuninnWebView: WKWebView {
    /// Open the page's HTML source (host wires this to a new tab).
    var onViewSource: ((MuninnWebView) -> Void)?
    /// Start a tracked download (Library) of a URL.
    var onDownload: ((URL) -> Void)?
    /// A local file was dropped onto the web view (host opens it in a tab).
    var onOpenFile: ((URL) -> Void)?
    /// Last right-clicked image / link (set from an injected `contextmenu` listener).
    var lastCtxImageURL: URL?
    var lastCtxLinkURL: URL?

    /// The first file URL on a drag pasteboard, if any.
    private static func fileURL(_ sender: NSDraggingInfo) -> URL? {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]
        return urls?.first(where: { $0.isFileURL })
    }

    // Intercept *file* drops to open them as tabs; defer every other drag (image/text/upload) to
    // WebKit so page drop-zones and drag-to-upload keep working.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURL(sender) != nil ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURL(sender) != nil ? .copy : super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = Self.fileURL(sender), let open = onOpenFile { open(url); return true }
        return super.performDragOperation(sender)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // Replace WebKit's native (untracked) "Download Image" with our tracked download items.
        if let i = menu.items.firstIndex(where: { $0.title.localizedCaseInsensitiveContains("Download Image") }) {
            menu.removeItem(at: i)
        }
        var addedSep = false
        func ensureSeparator() { if !addedSep { menu.addItem(.separator()); addedSep = true } }
        if let img = lastCtxImageURL {
            ensureSeparator()
            addDownloadItem(to: menu, "Save Image", img)
        }
        if let link = lastCtxLinkURL, link != lastCtxImageURL {
            ensureSeparator()
            addDownloadItem(to: menu, "Download Linked File", link)
        }
        // Page-level download — the only way to save a PDF you're *viewing* (WebKit renders it
        // inline, so it never becomes a WKDownload). Routes through the tracked `onDownload` path.
        if let url = url, let scheme = url.scheme, ["http", "https", "file"].contains(scheme) {
            ensureSeparator()
            let title = url.pathExtension.lowercased() == "pdf" ? "Download PDF" : "Save Page As…"
            addDownloadItem(to: menu, title, url)
        }

        guard AppSettings.developerMode else { return }
        // Replace WebKit's native (docked → blank/flicker in our custom window) "Inspect
        // Element" with our own that opens the inspector detached.
        if let i = menu.items.firstIndex(where: { $0.title.localizedCaseInsensitiveContains("Inspect Element") }) {
            menu.removeItem(at: i)
        }
        addItem(to: menu, "View Page Source", #selector(viewSourceMenu))
        addItem(to: menu, "Inspect Element", #selector(inspectMenu))
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func viewSourceMenu() { onViewSource?(self) }
    @objc private func inspectMenu() { showInspector() }

    private func addDownloadItem(to menu: NSMenu, _ title: String, _ url: URL) {
        let item = NSMenuItem(title: title, action: #selector(downloadFromMenu(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = url
        menu.addItem(item)
    }
    @objc private func downloadFromMenu(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { onDownload?(url) }
    }

    /// Open the in-app Web Inspector, detached as its own window (private API; guarded).
    ///
    /// WebKit opens the inspector docked *inside the inspected view's superview* — which here is
    /// our clipping, layout-managed web card, so a docked inspector renders blank and flickers.
    /// We detach it. `detach` only takes effect (and persists `InspectorStartsAttached = NO`)
    /// once the frontend is visible, so we poll `isVisible` first. After the first successful
    /// detach the preference sticks, so subsequent opens come up detached immediately.
    func showInspector() {
        if #available(macOS 13.3, *) { isInspectable = true }
        guard let inspector = perform(NSSelectorFromString("_inspector"))?.takeUnretainedValue() as? NSObject else { return }
        inspector.perform(NSSelectorFromString("show"))
        detachWhenVisible(inspector, attempts: 60)
    }

    /// `detach` only persists once the frontend is visible (WebKit sets `isVisible` after the
    /// inspector page loads), so poll — spaced over real time — before calling it. A no-op when
    /// already detached (e.g. the pre-seeded default), so it's a safety net across OS versions.
    private func detachWhenVisible(_ inspector: NSObject, attempts: Int) {
        guard attempts > 0 else { return }
        if (inspector.value(forKey: "isVisible") as? Bool) == true {
            inspector.perform(NSSelectorFromString("detach"))
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.detachWhenVisible(inspector, attempts: attempts - 1)
            }
        }
    }
}
