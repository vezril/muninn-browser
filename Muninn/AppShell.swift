import AppKit
import WebKit

/// The browser shell: a window with a tab bar, an address field, back/forward/reload,
/// and one-or-more `BrowserTab`s (each an injected `WKWebView` carrying the Pass content
/// shim). Owns the broker, the always-resident background host, and the per-tab page
/// contexts — so the auth-fork bus (page ⇄ broker ⇄ host) is live end to end.
@MainActor
final class AppShell: NSObject {
    private let window: NSWindow
    let broker: MessageBroker
    let host: BackgroundHost
    private var popup: PopupHost?

    // Tabs
    private var tabs: [BrowserTab] = []
    private var activeIndex = 0
    private var nextTabId = 0
    private let store = SidebarStore()
    private var activeTab: BrowserTab { tabs[activeIndex] }
    private var activeWebView: WKWebView { activeTab.webView }

    // Chrome
    private let addressField = NSTextField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let sidebar = NSView()
    private let tabStack = NSStackView()
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var sidebarOpen = true
    private let toggleButton = NSButton()
    private let revealButton = NSButton() // shown only when the sidebar is collapsed
    private static let sidebarWidth: CGFloat = 230
    private static let topInset: CGFloat = 8 // sidebar/content top padding below the title bar
    private let webContainer = NSView()
    private var keyMonitor: Any?
    /// Only during an explicit sign-in do we let the extension's `onInstalled` →
    /// `tabs.create` (the Proton onboarding page) drive the tab. In plain browsing it
    /// must NOT hijack the landing page.
    private let signInMode: Bool

    override init() {
        broker = MessageBroker()
        host = BackgroundHost(broker: broker)
        let env = ProcessInfo.processInfo.environment
        signInMode = env["MUNINN_FORKINIT"] != nil || env["MUNINN_POPUP"] != nil || env["MUNINN_SIGNIN"] != nil
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()

        // First tab (regular), then restore saved favourites/pinned (lazy).
        tabs.append(makeTab())
        for s in store.load() {
            guard let url = URL(string: s.url) else { continue }
            let tab = makeTab()
            tab.kind = s.kind
            tab.pendingURL = url
            tab.setInitialTitle(s.title)
            tabs.append(tab)
        }

        // The auth-fork is background-driven: background.js opens the fork URL via
        // tabs.create/windows.create. Route those to the active tab, and — the fork-init
        // the popup normally does — store the fork `localState` under
        // `storage.session["f"+state]` for the URL's `state` nonce so consume matches.
        broker.onOpenURL = { [weak self] url, _ in
            guard let self, self.signInMode else { return } // don't hijack plain browsing
            self.storeForkStateIfPresent(url)
            self.activeTab.load(url)
        }

        installGateLogging()
        host.start() // background.js resident; may open the fork URL immediately
        buildUI()
        showActiveWebView()

        loadLanding(activeTab) // default new-tab page (auth-fork paths override in present())
        window.title = "Muninn"
        window.center()
    }

    func present() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
        let env = ProcessInfo.processInfo.environment
        func proceed() {
            if env["MUNINN_FORKINIT"] != nil { doForkInit() }
            else if env["MUNINN_POPUP"] != nil { openPopup() }
            else { loadLanding(activeTab) } // plain browser: the landing page

        }
        // MUNINN_FRESH: wipe Muninn's OWN default website data (its store — NOT the
        // system browser) so an account login is fresh and actually forks.
        if env["MUNINN_FRESH"] != nil {
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                    modifiedSince: .distantPast) { proceed() }
        } else { proceed() }
    }

    // MARK: - tabs

    private func makeTab() -> BrowserTab {
        let id = nextTabId; nextTabId += 1
        let tab = BrowserTab(id: id, broker: broker)
        tab.onChange = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.rebuildTabBar()
            if tab === self.activeTab {
                self.updateChrome()
                if let url = tab.webView.url { self.storeForkStateIfPresent(url) }
            }
        }
        return tab
    }

    @objc func newTab() {
        tabs.append(makeTab())
        activeIndex = tabs.count - 1
        showActiveWebView()
        rebuildTabBar()
        loadLanding(activeTab)
        window.makeFirstResponder(addressField)
    }

    /// Muninn's new-tab landing page: a search box (DuckDuckGo, or a typed URL) — a
    /// placeholder we can grow into a real start page later.
    private func loadLanding(_ tab: BrowserTab) {
        tab.webView.loadHTMLString(Self.landingHTML, baseURL: URL(string: "https://duckduckgo.com/"))
    }

    private static let landingHTML = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      html,body{margin:0;height:100%}
      body{display:flex;flex-direction:column;align-items:center;justify-content:center;
        font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f6f6fb;color:#1a1a2e}
      h1{font-size:46px;font-weight:650;letter-spacing:-1.5px;margin:0}
      .sub{color:#6a6a88;margin:6px 0 30px;font-size:14px}
      form{width:min(600px,82vw)}
      input{width:100%;box-sizing:border-box;padding:15px 20px;font-size:16px;border-radius:14px;
        border:1px solid #dcdce8;background:#fff;color:#111;outline:none;
        box-shadow:0 2px 14px rgba(30,30,60,.06)}
      input:focus{border-color:#7777f8;box-shadow:0 2px 20px rgba(119,119,248,.18)}
      @media (prefers-color-scheme: dark){
        body{background:#16161f;color:#e8e8f2}.sub{color:#8a8aa8}
        input{background:#22222e;border-color:#33334d;color:#fff;box-shadow:none}
        input:focus{border-color:#7777f8}
      }
    </style></head><body>
      <h1>Muninn</h1><div class="sub">Private. Native. Yours.</div>
      <form action="https://duckduckgo.com/" method="get" autocomplete="off">
        <input name="q" placeholder="Search or enter a URL" autofocus>
      </form>
      <script>
        document.querySelector('form').addEventListener('submit', function (e) {
          var q = document.querySelector('input').value.trim();
          if (q && !/\\s/.test(q) && (/^https?:\\/\\//.test(q) || /^[\\w-]+(\\.[\\w-]+)+/.test(q))) {
            e.preventDefault();
            location.href = /^https?:\\/\\//.test(q) ? q : 'https://' + q;
          }
        });
      </script>
    </body></html>
    """

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        activeTab.ensureLoaded() // lazily load a restored favourite/pinned tab
        showActiveWebView()
        rebuildTabBar()
    }

    /// Persist favourites + pinned tabs (regular are session-only).
    private func persist() {
        store.save(tabs.filter { $0.kind != .regular }.compactMap { $0.saved() })
    }

    private func setKind(_ index: Int, _ kind: TabKind) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].kind = kind
        animatedRebuild()
        persist()
    }

    /// Rebuild the sidebar with a quick crossfade — makes a tab moving between
    /// sections (pin/favourite) feel fluid rather than snapping.
    private func animatedRebuild() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            tabStack.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.rebuildTabBar()
            self.tabStack.alphaValue = 0.0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                self.tabStack.animator().alphaValue = 1.0
            }
        })
    }
    @objc private func pinTab(_ s: NSMenuItem) { setKind(s.tag, .pinned) }
    @objc private func favouriteTab(_ s: NSMenuItem) { setKind(s.tag, .favourite) }
    @objc private func unclassifyTab(_ s: NSMenuItem) { setKind(s.tag, .regular) }
    @objc private func closeTabMenu(_ s: NSMenuItem) { closeTab(s.tag) }

    /// Right-click menu for a tab at `index` (favourite/pin/close).
    private func tabContextMenu(_ index: Int) -> NSMenu {
        let menu = NSMenu()
        let kind = tabs[index].kind
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: ""); m.target = self; m.tag = index; return m
        }
        if kind == .favourite { menu.addItem(item("Remove from Favourites", #selector(unclassifyTab(_:)))) }
        else { menu.addItem(item("Add to Favourites", #selector(favouriteTab(_:)))) }
        if kind == .pinned { menu.addItem(item("Unpin Tab", #selector(unclassifyTab(_:)))) }
        else if kind != .favourite { menu.addItem(item("Pin Tab", #selector(pinTab(_:)))) }
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(closeTabMenu(_:))))
        return menu
    }

    @objc func closeActiveTab() { closeTab(activeIndex) }

    func closeTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        if tabs.count == 1 { window.performClose(nil); return } // last tab → close window
        tabs[index].stop()
        tabs.remove(at: index)
        activeIndex = min(activeIndex, tabs.count - 1)
        showActiveWebView()
        rebuildTabBar()
        persist()
    }

    private func showActiveWebView() {
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        let web = activeWebView
        web.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: webContainer.topAnchor),
            web.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor),
        ])
        updateChrome()
    }

    /// Address field + nav-button state reflect the active tab.
    private func updateChrome() {
        addressField.stringValue = activeWebView.url?.absoluteString ?? ""
        backButton.isEnabled = activeWebView.canGoBack
        forwardButton.isEnabled = activeWebView.canGoForward
    }

    private func rebuildTabBar() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let favs = tabs.enumerated().filter { $0.element.kind == .favourite }
        let pins = tabs.enumerated().filter { $0.element.kind == .pinned }
        let regs = tabs.enumerated().filter { $0.element.kind == .regular }

        if !favs.isEmpty { tabStack.addArrangedSubview(favouritesRow(favs)) }
        for (i, tab) in pins { tabStack.addArrangedSubview(makeTabChip(tab, index: i, active: i == activeIndex)) }
        if !favs.isEmpty || !pins.isEmpty { tabStack.addArrangedSubview(separatorLine()) }
        for (i, tab) in regs { tabStack.addArrangedSubview(makeTabChip(tab, index: i, active: i == activeIndex)) }
        tabStack.addArrangedSubview(newTabRow())
    }

    private func newTabRow() -> NSView {
        let plus = NSButton(title: " New Tab",
                            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")!,
                            target: self, action: #selector(newTab))
        plus.imagePosition = .imageLeading
        plus.isBordered = false
        plus.font = .systemFont(ofSize: 12)
        plus.contentTintColor = .secondaryLabelColor
        plus.alignment = .left
        plus.translatesAutoresizingMaskIntoConstraints = false
        plus.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16).isActive = true
        plus.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return plus
    }

    private func separatorLine() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16).isActive = true
        return box
    }

    /// Favourites as larger avatar icons, wrapped into rows.
    private func favouritesRow(_ favs: [(offset: Int, element: BrowserTab)]) -> NSView {
        let perRow = 5
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        for chunk in stride(from: 0, to: favs.count, by: perRow).map({ Array(favs[$0..<min($0 + perRow, favs.count)]) }) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            for (i, tab) in chunk { row.addArrangedSubview(makeFavouriteIcon(tab, index: i)) }
            column.addArrangedSubview(row)
        }
        return column
    }

    private func makeFavouriteIcon(_ tab: BrowserTab, index: Int) -> NSView {
        let icon = TabChipView()
        icon.index = index
        icon.onSelect = { [weak self] in self?.selectTab(index) }
        icon.menu = tabContextMenu(index)
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 9
        icon.layer?.backgroundColor = tab.avatarColor.cgColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 38).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 38).isActive = true
        if index == activeIndex {
            icon.layer?.borderWidth = 2
            icon.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
        let letter = NSTextField(labelWithString: tab.avatarLetter)
        letter.font = .systemFont(ofSize: 16, weight: .semibold)
        letter.textColor = .white
        letter.translatesAutoresizingMaskIntoConstraints = false
        icon.addSubview(letter)
        NSLayoutConstraint.activate([
            letter.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            letter.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
        ])
        icon.toolTip = tab.title
        return icon
    }

    /// One tab row: title (left) + `×` (right) INSIDE a single full-width, clickable pill.
    private func makeTabChip(_ tab: BrowserTab, index: Int, active: Bool) -> NSView {
        let chip = TabChipView()
        chip.index = index
        chip.onSelect = { [weak self] in self?.selectTab(index) }
        chip.menu = tabContextMenu(index) // right-click: pin / favourite / close
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 7
        chip.layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
            : NSColor.clear.cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16).isActive = true
        chip.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let title = NSTextField(labelWithString: tab.title)
        title.font = .systemFont(ofSize: 12, weight: active ? .semibold : .regular)
        title.textColor = active ? .labelColor : .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        let close = HoverCloseButton(image: xmark ?? NSImage(), target: self, action: #selector(tabChipClosed(_:)))
        close.tag = index
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.contentTintColor = .secondaryLabelColor
        close.translatesAutoresizingMaskIntoConstraints = false
        close.widthAnchor.constraint(equalToConstant: 16).isActive = true
        close.heightAnchor.constraint(equalToConstant: 16).isActive = true

        chip.addSubview(title); chip.addSubview(close)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 11),
            title.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -6),
            close.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -6),
        ])
        return chip
    }

    @objc private func tabChipClosed(_ sender: NSButton) { closeTab(sender.tag) }

    // MARK: - auth-fork (parked; runs on the active tab)

    func storeForkStateIfPresent(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return }
        var state = items.first(where: { $0.name == "state" })?.value
        if state == nil, let lp = items.first(where: { $0.name == "loginParams" })?.value {
            for pair in lp.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, kv[0] == "state" { state = String(kv[1]) }
            }
        }
        guard let s = state, !s.isEmpty else { return }
        broker.storage.set(.session, ["f\(s)": "{}"])
    }

    private func doForkInit() {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let nonce = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        broker.storage.set(.session, ["f\(nonce)": "{}"])
        navigate(to: "https://account.proton.me/authorize?app=proton-pass-extension"
            + "&state=\(nonce)&independent=0&prompt=login&promptBypass=sso&promptType=offline&pt=offline&t=3")
    }

    func openPopup() {
        let p = PopupHost(broker: broker)
        self.popup = p
        p.load()
        p.present()
    }

    // MARK: - UI

    private func buildUI() {
        configureButton(toggleButton, symbol: "sidebar.left", action: #selector(toggleSidebar))
        configureButton(backButton, symbol: "chevron.backward", action: #selector(goBack))
        configureButton(forwardButton, symbol: "chevron.forward", action: #selector(goForward))
        configureButton(reloadButton, symbol: "arrow.clockwise", action: #selector(reload))
        configureButton(revealButton, symbol: "sidebar.left", action: #selector(toggleSidebar))
        revealButton.isHidden = true // only when collapsed

        addressField.placeholderString = "Search or enter a URL"
        addressField.target = self
        addressField.action = #selector(addressSubmitted)
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.font = .systemFont(ofSize: 13)

        // Nav cluster — top of the sidebar, under the window buttons.
        let navRow = NSStackView(views: [toggleButton, backButton, forwardButton, reloadButton])
        navRow.orientation = .horizontal
        navRow.spacing = 4
        navRow.translatesAutoresizingMaskIntoConstraints = false

        // Left sidebar: nav row + vertical tab list, collapsible.
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        sidebar.layer?.masksToBounds = true
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        tabStack.orientation = .vertical
        tabStack.alignment = .leading
        tabStack.spacing = 3
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(navRow)
        sidebar.addSubview(addressField) // Arc-style: URL bar in the sidebar, under nav
        sidebar.addSubview(tabStack)
        NSLayoutConstraint.activate([
            navRow.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: Self.topInset),
            navRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            addressField.topAnchor.constraint(equalTo: navRow.bottomAnchor, constant: 8),
            addressField.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            addressField.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16),
            tabStack.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 12),
            tabStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            tabStack.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16),
        ])

        // Right area: just the web content (full height).
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(sidebar)
        content.addSubview(webContainer)
        content.addSubview(revealButton) // floats top-left when the sidebar is hidden
        window.contentView = content

        sidebarWidthConstraint = sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth)
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebarWidthConstraint,
            webContainer.topAnchor.constraint(equalTo: content.topAnchor),
            webContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            revealButton.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.topInset),
            revealButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
        ])
        rebuildTabBar()
    }

    @objc private func toggleSidebar() {
        sidebarOpen.toggle()
        tabStack.isHidden = !sidebarOpen
        revealButton.isHidden = sidebarOpen
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            sidebarWidthConstraint.animator().constant = sidebarOpen ? Self.sidebarWidth : 0
        }
    }

    private func configureButton(_ b: NSButton, symbol: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.bezelStyle = .texturedRounded
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 34).isActive = true
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.modifierFlags.contains(.command) else { return e }
            switch e.charactersIgnoringModifiers {
            case "t": self.newTab(); return nil
            case "w": self.closeActiveTab(); return nil
            case "l": self.window.makeFirstResponder(self.addressField); return nil
            case "r": self.reload(); return nil
            default: return e
            }
        }
    }

    // MARK: - actions (active tab)

    private func navigate(to string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return }
        activeTab.load(url)
    }

    @objc private func addressSubmitted() { navigate(to: addressField.stringValue) }
    @objc private func goBack() { activeWebView.goBack() }
    @objc private func goForward() { activeWebView.goForward() }
    @objc private func reload() { activeWebView.reload() }

    private func installGateLogging() {
        guard ProcessInfo.processInfo.environment["MUNINN_E6_GATE"] != nil else { return }
        let logPath = ProcessInfo.processInfo.environment["MUNINN_E6_GATE_LOG"]
        func gate(_ line: String) {
            let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
            if let p = logPath {
                if !FileManager.default.fileExists(atPath: p) { FileManager.default.createFile(atPath: p, contents: nil) }
                if let fh = FileHandle(forWritingAtPath: p) { fh.seekToEndOfFile(); fh.write(Data(stamped.utf8)); try? fh.close() }
            }
            FileHandle.standardError.write(Data(stamped.utf8))
        }
        broker.onCrossContextRelay = { direction, senderHost in gate("E6-GATE \(direction) from \(senderHost)") }
        broker.onExternalRelay = { type, senderHost, responded in
            gate("E6-GATE ext-msg type=\(type) from \(senderHost) " + (responded ? "→ RESPONDED" : "→ sent")) }
        broker.onFetchProbe = { method, host, status, errored in
            gate("E6-GATE fetch \(method) \(host) → " + (errored ? "ERR" : "\(status)")) }
        broker.onAudit = { entry in
            if (entry["kind"] as? String) == "open-url" { gate("E6-GATE open-url \(entry["member"] ?? "?") -> \(entry["url"] ?? "?")") }
        }
        host.onBootEvent = { e in
            let k = e["kind"] as? String ?? "?"
            if ["workerError", "workerRejection"].contains(k) { gate("E6-GATE \(k)") }
            else if k == "host:backgroundLoaded" { gate("E6-GATE background-loaded") }
            else if k == "console", let text = e["text"] as? String {
                let markers = ["Invalid fork state", "missing permissions", "consumeFork",
                               "fork state", "InactiveSession", "pullFork"]
                if let hit = markers.first(where: { text.localizedCaseInsensitiveContains($0) }) {
                    gate("E6-GATE bg-marker: \(hit)")
                }
            }
        }
    }
}
