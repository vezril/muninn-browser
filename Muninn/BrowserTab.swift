import AppKit
import WebKit

/// Where a tab lives in the sidebar. `favourite` = large icon at the top; `pinned` =
/// persistent chip above the separator; `regular` = ephemeral chip below it.
enum TabKind: String, Codable { case favourite, pinned, regular }

/// Persisted representation of a favourite/pinned tab (restored on next launch).
struct SavedTab: Codable {
    var url: String; var title: String; var kind: TabKind
    var faviconBase64: String?
    /// UUID (string) of the folder this pinned tab belongs to, if any.
    var folderId: String?
    /// UUID (string) of the owning workspace (optional for migration).
    var workspaceId: String?
}

extension NSColor {
    /// Parse "#RRGGBB" (or "RRGGBB"). Returns nil on malformed input.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    /// "#RRGGBB" in sRGB.
    var toHex: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

/// A container view that reports when the cursor leaves it — used for the sidebar's
/// hover-peek (slide back when the pointer moves off the floating sidebar).
final class HoverView: NSView {
    var onEntered: (() -> Void)?
    var onExited: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a); area = nil }
        guard onExited != nil || onEntered != nil else { return }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }
    override func mouseEntered(with e: NSEvent) { onEntered?() }
    override func mouseExited(with e: NSEvent) { onExited?() }
}

/// What a drag carries: a tab (by stable id) or a folder (by id).
enum DragPayload { case tab(Int); case folder(UUID) }

/// Where within a drop target the cursor is: reorder above/below, or drop *onto* it (split).
enum DropZone { case before, after, onto }

/// A tab-bar chip / folder header. A plain click selects (fired on mouse-up if no drag
/// happened); the close button, being a subview, consumes its own clicks. Acts as a drag
/// source (set `dragTab` or `dragFolder`) and a reorder-aware drop target (set `onDrop`,
/// which receives the payload and whether to insert *before* this row).
final class TabChipView: NSView, NSDraggingSource {
    static let tabType = NSPasteboard.PasteboardType("com.vezril.muninn.tab")
    static let folderType = NSPasteboard.PasteboardType("com.vezril.muninn.folder")

    override var isFlipped: Bool { true } // top-left origin → "before" = upper/left half

    var index: Int = 0
    var onSelect: (() -> Void)?
    var dragTab: Int?          // draggable as a tab
    var dragFolder: UUID?      // draggable as a folder
    var dropHorizontal = false // favourites row: decide before/after by x, not y
    var dropSupportsOnto = false // enable a center "drop onto" (split) zone
    /// (payload, zone) — nil = not a drop target.
    var onDrop: ((DragPayload, DropZone) -> Void)?
    /// Hover in/out (nil = no hover tracking) — used for workspace name peeks.
    var onHover: ((Bool) -> Void)?

    private var mouseDownAt: NSPoint?
    private var dragging = false
    private var hoverArea: NSTrackingArea?
    private lazy var dropLine: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        v.layer?.cornerRadius = 1
        v.isHidden = true
        addSubview(v)
        return v
    }()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if onDrop != nil { registerForDraggedTypes([Self.tabType, Self.folderType]) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let h = hoverArea { removeTrackingArea(h); hoverArea = nil }
        guard onHover != nil else { return }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a); hoverArea = a
    }
    override func mouseEntered(with e: NSEvent) { onHover?(true) }
    override func mouseExited(with e: NSEvent) { onHover?(false) }

    // MARK: click vs drag
    override func mouseDown(with e: NSEvent) { mouseDownAt = e.locationInWindow; dragging = false }
    override func mouseDragged(with e: NSEvent) {
        guard !dragging, let start = mouseDownAt else { return }
        let dx = e.locationInWindow.x - start.x, dy = e.locationInWindow.y - start.y
        guard dx * dx + dy * dy > 16 else { return } // 4pt threshold
        let item = NSPasteboardItem()
        if let t = dragTab { item.setString(String(t), forType: Self.tabType) }
        else if let f = dragFolder { item.setString(f.uuidString, forType: Self.folderType) }
        else { return }
        dragging = true
        let drag = NSDraggingItem(pasteboardWriter: item)
        drag.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [drag], event: e, source: self)
    }
    override func mouseUp(with e: NSEvent) {
        if !dragging { onSelect?() }
        mouseDownAt = nil; dragging = false
    }
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        dragging = false; mouseDownAt = nil
    }

    private func snapshot() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return NSImage(size: bounds.size) }
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size); img.addRepresentation(rep); return img
    }

    // MARK: drop target
    private func payload(_ s: NSDraggingInfo) -> DragPayload? {
        let pb = s.draggingPasteboard
        if let t = pb.string(forType: Self.tabType).flatMap({ Int($0) }) { return .tab(t) }
        if let f = pb.string(forType: Self.folderType).flatMap({ UUID(uuidString: $0) }) { return .folder(f) }
        return nil
    }
    private func zone(_ s: NSDraggingInfo) -> DropZone {
        let p = convert(s.draggingLocation, from: nil)
        if dropHorizontal { return p.x < bounds.midX ? .before : .after }
        if dropSupportsOnto {
            let h = bounds.height
            if p.y < h / 3 { return .before }
            if p.y > h * 2 / 3 { return .after }
            return .onto
        }
        return p.y < bounds.midY ? .before : .after
    }
    private func accepts(_ s: NSDraggingInfo) -> Bool {
        guard onDrop != nil, let p = payload(s) else { return false }
        if case let .tab(t) = p, dragTab == t { return false } // don't drop onto self
        if case let .folder(f) = p, dragFolder == f { return false }
        return true
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { updateDrop(s) }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { updateDrop(s) }
    override func draggingExited(_ s: NSDraggingInfo?) { dropLine.isHidden = true; layer?.borderWidth = 0 }
    private func updateDrop(_ s: NSDraggingInfo) -> NSDragOperation {
        guard accepts(s) else { dropLine.isHidden = true; layer?.borderWidth = 0; return [] }
        let z = zone(s)
        let t: CGFloat = 2
        if z == .onto {
            dropLine.isHidden = true
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            layer?.borderWidth = 0
            dropLine.isHidden = false
            if dropHorizontal {
                dropLine.frame = NSRect(x: z == .before ? 0 : bounds.width - t, y: 2, width: t, height: bounds.height - 4)
            } else {
                dropLine.frame = NSRect(x: 2, y: z == .before ? 0 : bounds.height - t, width: bounds.width - 4, height: t)
            }
        }
        return .move
    }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool { accepts(s) }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        dropLine.isHidden = true; layer?.borderWidth = 0
        guard accepts(s), let p = payload(s), let handler = onDrop else { return false }
        handler(p, zone(s)); return true
    }
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
    /// If pinned, the folder it lives in (nil = ungrouped pinned).
    var folderId: UUID?
    /// The workspace this tab belongs to.
    var workspaceId: UUID?
    /// Tabs sharing a split-group id render as one combined sidebar tab + a split view.
    var splitGroupId: UUID?
    /// For pinned/favourite tabs: the site it's anchored to. Cross-site link clicks open a
    /// Peek preview instead of navigating the tab away from here.
    var homeURL: URL?
    /// Whether this tab is currently playing media (drives the Mini Player).
    var isPlayingMedia = false
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

    init(id: Int, broker: MessageBroker, dataStore: WKWebsiteDataStore? = nil) {
        self.id = id
        self.injector = InjectionCoordinator(broker: broker, contextName: "page-\(id)", dataStore: dataStore)
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

    /// Blank the page to free its memory but keep the tab (favourite/pinned) restorable —
    /// it reloads lazily via `ensureLoaded()` the next time it's selected.
    func unload() {
        guard isLoaded else { return }
        pendingURL = webView.url ?? pendingURL
        isLoaded = false
        faviconForURL = nil
        if let blank = URL(string: "about:blank") { injector.load(blank) }
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
        return SavedTab(url: u, title: title, kind: kind,
                        faviconBase64: faviconData?.base64EncodedString(),
                        folderId: folderId?.uuidString,
                        workspaceId: workspaceId?.uuidString)
    }

    func stop() {
        titleObs = nil; urlObs = nil; loadingObs = nil
        injector.stop()
    }
}
