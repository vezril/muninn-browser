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
    private var activeTab: BrowserTab { tabs[activeIndex] }
    private var activeWebView: WKWebView { activeTab.webView }

    // Chrome
    private let addressField = NSTextField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let tabBar = NSStackView()
    private let webContainer = NSView()
    private var keyMonitor: Any?

    override init() {
        broker = MessageBroker()
        host = BackgroundHost(broker: broker)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()

        // First tab.
        tabs.append(makeTab())

        // The auth-fork is background-driven: background.js opens the fork URL via
        // tabs.create/windows.create. Route those to the active tab, and — the fork-init
        // the popup normally does — store the fork `localState` under
        // `storage.session["f"+state]` for the URL's `state` nonce so consume matches.
        var didOpen = false
        broker.onOpenURL = { [weak self] url, _ in
            didOpen = true
            self?.storeForkStateIfPresent(url)
            self?.activeTab.load(url)
        }

        installGateLogging()
        host.start() // background.js resident; may open the fork URL immediately
        buildUI()
        showActiveWebView()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if !didOpen { self?.navigate(to: "https://account.proton.me") }
        }
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
            else { navigate(to: "https://account.proton.me") }
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
        navigate(to: "https://account.proton.me") // simple default home
        window.makeFirstResponder(addressField)
    }

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        showActiveWebView()
        rebuildTabBar()
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
        tabBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, tab) in tabs.enumerated() {
            tabBar.addArrangedSubview(makeTabChip(tab, index: i, active: i == activeIndex))
        }
        let plus = NSButton(title: "+", target: self, action: #selector(newTab))
        plus.bezelStyle = .texturedRounded
        plus.setButtonType(.momentaryPushIn)
        plus.widthAnchor.constraint(equalToConstant: 30).isActive = true
        tabBar.addArrangedSubview(plus)
    }

    private func makeTabChip(_ tab: BrowserTab, index: Int, active: Bool) -> NSView {
        let titleBtn = NSButton(title: chipTitle(tab), target: self, action: #selector(tabChipClicked(_:)))
        titleBtn.tag = index
        titleBtn.bezelStyle = .texturedRounded
        titleBtn.setButtonType(.pushOnPushOff)
        titleBtn.state = active ? .on : .off
        titleBtn.alignment = .left
        titleBtn.lineBreakMode = .byTruncatingTail
        titleBtn.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let close = NSButton(title: "×", target: self, action: #selector(tabChipClosed(_:)))
        close.tag = index
        close.bezelStyle = .texturedRounded
        close.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let chip = NSStackView(views: [titleBtn, close])
        chip.orientation = .horizontal
        chip.spacing = 2
        return chip
    }

    private func chipTitle(_ tab: BrowserTab) -> String {
        let t = tab.title
        return t.count > 22 ? String(t.prefix(22)) + "…" : t
    }

    @objc private func tabChipClicked(_ sender: NSButton) { selectTab(sender.tag) }
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
        configureButton(backButton, symbol: "chevron.backward", action: #selector(goBack))
        configureButton(forwardButton, symbol: "chevron.forward", action: #selector(goForward))
        configureButton(reloadButton, symbol: "arrow.clockwise", action: #selector(reload))

        addressField.placeholderString = "Enter a URL"
        addressField.target = self
        addressField.action = #selector(addressSubmitted)
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.font = .systemFont(ofSize: 13)

        let toolbar = NSStackView(views: [backButton, forwardButton, reloadButton, addressField])
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.setHuggingPriority(.defaultLow, for: .horizontal)

        tabBar.orientation = .horizontal
        tabBar.spacing = 4
        tabBar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 0, right: 8)
        tabBar.alignment = .centerY
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.setHuggingPriority(.defaultLow, for: .horizontal)

        webContainer.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(tabBar)
        content.addSubview(toolbar)
        content.addSubview(webContainer)
        window.contentView = content

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: content.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        rebuildTabBar()
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
