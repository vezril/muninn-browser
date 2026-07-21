import AppKit
import WebKit

/// Where a tab lives in the sidebar. `favourite` = large icon at the top; `pinned` =
/// persistent chip above the separator; `regular` = ephemeral chip below it.
enum TabKind: String, Codable { case favourite, pinned, regular }

/// Persisted representation of a favourite/pinned tab (restored on next launch).
struct SavedTab: Codable { var url: String; var title: String; var kind: TabKind; var faviconBase64: String? }

/// A tab-bar chip. Selection is via `mouseDown` (which the close button, being a
/// subview, naturally consumes — so clicking × never also selects the tab).
final class TabChipView: NSView {
    var index: Int = 0
    var onSelect: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onSelect?() }
}

/// Close button that highlights on hover.
final class HoverCloseButton: NSButton {
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) {
        wantsLayer = true
        layer?.cornerRadius = bounds.height / 2 // circular
        layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.25).cgColor
        contentTintColor = .labelColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        contentTintColor = .secondaryLabelColor
    }
}

/// One browser tab: an injected `WKWebView` (the Pass content shim rides along, per-tab
/// broker context) plus its title/url tracking for the tab bar and address field.
@MainActor
final class BrowserTab {
    let id: Int
    let injector: InjectionCoordinator
    var webView: WKWebView { injector.webView }

    /// Sidebar section this tab belongs to.
    var kind: TabKind = .regular
    /// URL a restored favourite/pinned tab should load lazily on first activation.
    var pendingURL: URL?
    /// Whether this tab's webView has loaded anything yet (lazy restore).
    var isLoaded = false

    /// Display title (page title, falling back to host / "New Tab").
    private(set) var title: String = "New Tab"
    /// The site's own favicon (fetched from its origin — no third-party service).
    private(set) var favicon: NSImage?
    private var faviconData: Data?
    private var faviconForURL: String?
    /// Fired when the tab's title or url changes (so the shell can refresh the UI).
    var onChange: (() -> Void)?

    private var titleObs: NSKeyValueObservation?
    private var urlObs: NSKeyValueObservation?
    private var loadingObs: NSKeyValueObservation?

    init(id: Int, broker: MessageBroker) {
        self.id = id
        self.injector = InjectionCoordinator(broker: broker, contextName: "page-\(id)")
        titleObs = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.refreshTitle(wv); self?.onChange?() }
        }
        urlObs = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.refreshTitle(wv); self?.onChange?() }
        }
        // Fetch the favicon only once a page has finished loading — its DOM (and
        // location.origin) is then the real page, not the outgoing one.
        loadingObs = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated { self?.fetchFaviconIfNeeded() }
        }
    }

    /// Restore a cached favicon (from persistence) so a favourite shows its icon before load.
    func setInitialFavicon(base64: String?) {
        guard let base64, let data = Data(base64Encoded: base64), let img = NSImage(data: data) else { return }
        favicon = img; faviconData = data
    }

    /// Fetch the page's OWN favicon (its `<link rel=icon>` or `/favicon.ico`, from the
    /// site's origin — never a third-party favicon service). Once per page.
    private func fetchFaviconIfNeeded() {
        guard isLoaded, let page = webView.url, page.scheme?.hasPrefix("http") == true else { return }
        // Key by origin: one favicon per site, re-fetched when the origin changes.
        let key = (page.scheme ?? "") + "://" + (page.host ?? "")
        if faviconForURL == key { return }
        faviconForURL = key
        let js = "(function(){var l=document.querySelector('link[rel~=\"icon\"],link[rel=\"shortcut icon\"],link[rel=\"apple-touch-icon\"]');return l&&l.href?l.href:(location.origin+'/favicon.ico');})()"
        webView.evaluateJavaScript(js) { [weak self] res, _ in
            guard let self, let href = res as? String, let u = URL(string: href) else { return }
            URLSession.shared.dataTask(with: u) { data, _, _ in
                guard let data, !data.isEmpty, let img = NSImage(data: data), img.isValid else { return }
                Task { @MainActor in self.favicon = img; self.faviconData = data; self.onChange?() }
            }.resume()
        }
    }

    private func refreshTitle(_ wv: WKWebView) {
        if let t = wv.title, !t.isEmpty { title = t }
        else if let h = wv.url?.host { title = h }
        else if title == "New Tab", let h = pendingURL?.host { title = h }
    }

    /// Set a display title for a restored (not-yet-loaded) tab.
    func setInitialTitle(_ t: String) { if !t.isEmpty { title = t } }

    func load(_ url: URL) { pendingURL = nil; isLoaded = true; injector.load(url) }

    /// Lazily load a restored favourite/pinned tab the first time it's shown.
    func ensureLoaded() {
        guard !isLoaded, let u = pendingURL else { return }
        load(u)
    }

    /// The tab's current or pending URL (for persistence).
    var currentURL: URL? { webView.url ?? pendingURL }

    /// A stable letter + colour for the favourite avatar (privacy-first — no favicon fetch).
    var avatarLetter: String {
        let host = currentURL?.host ?? title
        let s = host.replacingOccurrences(of: "www.", with: "")
        return String(s.first ?? "•").uppercased()
    }
    var avatarColor: NSColor {
        let key = currentURL?.host ?? title
        let hue = CGFloat(abs(key.hashValue) % 360) / 360.0
        return NSColor(hue: hue, saturation: 0.55, brightness: 0.75, alpha: 1)
    }

    func saved() -> SavedTab? {
        guard let u = currentURL?.absoluteString, !u.isEmpty, !u.hasPrefix("about:") else { return nil }
        return SavedTab(url: u, title: title, kind: kind, faviconBase64: faviconData?.base64EncodedString())
    }

    func stop() {
        titleObs = nil; urlObs = nil; loadingObs = nil
        injector.stop()
    }
}
