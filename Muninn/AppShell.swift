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
    /// Pinned-tab folders (collapsible, renamable, colourable).
    private var folders: [Folder] = []
    /// Workspaces (each owns its favourites / pins / folders / regular tabs).
    private var workspaces: [Workspace] = []
    private var activeWorkspaceId = UUID()
    /// Remembers the last-active tab id per workspace (restored on switch).
    private var lastActiveTabId: [UUID: Int] = [:]
    private let workspaceBar = NSStackView()
    /// Floating name shown while hovering a workspace chip.
    private let workspaceHoverLabel = NSTextField(labelWithString: "")
    /// Workspace currently targeted by the live NSColorPanel.
    private var colorPickWorkspace: UUID?
    private var activeTab: BrowserTab { tabs[activeIndex] }
    private var activeWebView: WKWebView { activeTab.webView }

    // Chrome
    private let addressField = NSTextField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let sidebar = HoverView()
    private let tabStack = NSStackView()
    /// Slide offset of the sidebar (0 = shown, -sidebarWidth = tucked off-screen left).
    private var sidebarLeadingConstraint: NSLayoutConstraint!
    /// Web card leading pinned to the sidebar (docked) vs the window edge (collapsed/peek).
    private var webLeadingDocked: NSLayoutConstraint!
    private var webLeadingFull: NSLayoutConstraint!
    private var sidebarOpen = true  // pinned-open
    private var peeking = false     // temporarily revealed by hovering the left edge
    private let toggleButton = NSButton()
    private var mouseMonitor: Any?
    private static let sidebarWidth: CGFloat = 230
    private static let topInset: CGFloat = 30 // clears the traffic-light strip (full-size content)
    private static let webCardInset: CGFloat = 8 // margin around the floating web card
    private static let webCardTopInset: CGFloat = 34 // clears the transparent title bar
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        // Extend the (tinted) content under the traffic-light bar; no title text.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init()

        let saved = store.load()

        // Workspaces — migrate: ensure at least one, then resolve the active one.
        workspaces = saved.workspaces.isEmpty
            ? [Workspace(name: "Personal", icon: "🏠", colorHex: Self.folderColor(1).toHex)]
            : saved.workspaces
        let defaultWs = workspaces[0].id
        activeWorkspaceId = saved.activeWorkspace.flatMap(UUID.init)
            .flatMap { id in workspaces.contains { $0.id == id } ? id : nil } ?? defaultWs

        // Folders — assign any pre-workspaces folder to the default workspace.
        folders = saved.folders.map { var f = $0; if f.workspaceId == nil { f.workspaceId = defaultWs }; return f }
        let folderIds = Set(folders.map { $0.id })
        let wsIds = Set(workspaces.map { $0.id })

        // First (session) regular tab in the active workspace, then restore saved tabs.
        let first = makeTab(); first.workspaceId = activeWorkspaceId; tabs.append(first)
        for s in saved.tabs {
            guard let url = URL(string: s.url) else { continue }
            let tab = makeTab()
            tab.kind = s.kind
            tab.pendingURL = url
            tab.setInitialTitle(s.title)
            tab.setInitialFavicon(base64: s.faviconBase64)
            if let fid = s.folderId.flatMap(UUID.init), folderIds.contains(fid) { tab.folderId = fid }
            tab.workspaceId = s.workspaceId.flatMap(UUID.init).flatMap { wsIds.contains($0) ? $0 : nil } ?? defaultWs
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
        window.center()
    }

    func present() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
        installMouseMonitor()
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
        let tab = makeTab(); tab.workspaceId = activeWorkspaceId
        tabs.append(tab)
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
        lastActiveTabId[activeWorkspaceId] = tabs[index].id
        activeTab.ensureLoaded() // lazily load a restored favourite/pinned tab
        showActiveWebView()
        rebuildTabBar()
    }

    /// Persist favourites + pinned tabs, folders, and workspaces (regular tabs are session-only).
    private func persist() {
        // Drop empty folders that no pinned tab references (keeps state tidy).
        let used = Set(tabs.filter { $0.kind == .pinned }.compactMap { $0.folderId })
        folders.removeAll { !used.contains($0.id) }
        store.save(SidebarState(tabs: tabs.filter { $0.kind != .regular }.compactMap { $0.saved() },
                                folders: folders,
                                workspaces: workspaces,
                                activeWorkspace: activeWorkspaceId.uuidString))
    }

    private func setKind(_ index: Int, _ kind: TabKind) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].kind = kind
        if kind != .pinned { tabs[index].folderId = nil } // only pinned tabs live in folders
        rebuildTabBar() // instant — the rest of the list doesn't flash
        // Fade the moved tab in at its new section (targeted, no whole-list blink).
        if let v = chipView(for: index) {
            v.wantsLayer = true
            v.alphaValue = 0
            v.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: -6))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                v.animator().alphaValue = 1
                v.layer?.setAffineTransform(.identity)
            }
        }
        persist()
    }

    /// Find the chip/favourite view for a tab index anywhere in the sidebar tree.
    private func chipView(for index: Int, in view: NSView? = nil) -> NSView? {
        for sub in (view ?? tabStack).subviews {
            if let c = sub as? TabChipView, c.index == index { return c }
            if let found = chipView(for: index, in: sub) { return found }
        }
        return nil
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

        // Folders — available for any tab (moving a regular/favourite tab in pins it).
        if kind != .favourite || !folders.isEmpty {
            let move = NSMenuItem(title: "Add to Folder", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for folder in folders {
                let m = NSMenuItem(title: folder.name, action: #selector(moveTabToFolder(_:)), keyEquivalent: "")
                m.target = self; m.tag = index
                m.representedObject = folder.id.uuidString
                if tabs[index].folderId == folder.id { m.state = .on }
                sub.addItem(m)
            }
            if !folders.isEmpty { sub.addItem(.separator()) }
            sub.addItem(item("New Folder…", #selector(newFolderForTab(_:))))
            move.submenu = sub
            menu.addItem(move)
            if tabs[index].folderId != nil {
                menu.addItem(item("Remove from Folder", #selector(removeTabFromFolder(_:))))
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(closeTabMenu(_:))))
        return menu
    }

    // MARK: - folder actions

    @objc private func moveTabToFolder(_ s: NSMenuItem) {
        guard tabs.indices.contains(s.tag), let idStr = s.representedObject as? String,
              let fid = UUID(uuidString: idStr) else { return }
        tabs[s.tag].kind = .pinned
        tabs[s.tag].folderId = fid
        rebuildTabBar(); persist()
    }

    @objc private func removeTabFromFolder(_ s: NSMenuItem) {
        guard tabs.indices.contains(s.tag) else { return }
        tabs[s.tag].folderId = nil
        rebuildTabBar(); persist()
    }

    @objc private func newFolderForTab(_ s: NSMenuItem) {
        guard tabs.indices.contains(s.tag) else { return }
        guard let name = promptForText(title: "New Folder", message: "Name this folder:",
                                       initial: "Folder") else { return }
        let folder = Folder(name: name, colorIndex: folders.count % Folder.palette.count,
                            workspaceId: tabs[s.tag].workspaceId ?? activeWorkspaceId)
        folders.append(folder)
        tabs[s.tag].kind = .pinned
        tabs[s.tag].folderId = folder.id
        rebuildTabBar(); persist()
    }

    private func folderIndex(_ id: UUID) -> Int? { folders.firstIndex { $0.id == id } }
    private func tabIndex(id: Int) -> Int? { tabs.firstIndex { $0.id == id } }

    // MARK: drag & drop (reorder + move between sections/folders)

    /// A chip is a drag source (its stable tab id) and a drop target that reorders/moves
    /// the dropped tab to sit next to this one — inheriting this chip's section.
    private func configureDrag(_ chip: TabChipView, tab: BrowserTab, horizontal: Bool = false) {
        chip.dragTab = tab.id
        chip.dropHorizontal = horizontal
        chip.onDrop = { [weak self, weak tab] payload, before in
            guard let self, let tab, case let .tab(draggedId) = payload else { return }
            self.moveTab(draggedId, kind: tab.kind, folderId: tab.folderId, nextTo: tab.id, before: before)
        }
    }

    /// Move a tab to a section (kind + optional folder) and position it next to `targetId`
    /// (or at the end when nil). Preserves the active tab across the reorder.
    private func moveTab(_ id: Int, kind: TabKind, folderId: UUID?, nextTo targetId: Int?, before: Bool) {
        guard id != targetId, let from = tabIndex(id: id) else { return }
        let active = activeTab
        let tab = tabs.remove(at: from)
        tab.kind = kind
        tab.folderId = (kind == .pinned) ? folderId : nil
        var insertAt = tabs.count
        if let targetId, let t = tabIndex(id: targetId) { insertAt = before ? t : t + 1 }
        tabs.insert(tab, at: min(max(insertAt, 0), tabs.count))
        if let ai = tabs.firstIndex(where: { $0 === active }) { activeIndex = ai }
        rebuildTabBar(); persist()
    }

    /// Reorder a folder next to another folder.
    private func moveFolder(_ id: UUID, nextTo targetId: UUID, before: Bool) {
        guard id != targetId, let from = folderIndex(id) else { return }
        let f = folders.remove(at: from)
        let t = folderIndex(targetId) ?? folders.count
        folders.insert(f, at: min(max(before ? t : t + 1, 0), folders.count))
        rebuildTabBar(); persist()
    }

    // MARK: - workspaces

    private func workspaceIndex(_ id: UUID) -> Int? { workspaces.firstIndex { $0.id == id } }

    private static let defaultWorkspaceIcons = ["🏠", "💼", "🎨", "📚", "🎮", "🛒", "⭐️", "🌙"]

    /// The workspace's background-tint colour (hex → legacy index → default).
    private func wsColor(_ ws: Workspace) -> NSColor {
        if let hex = ws.colorHex, let c = NSColor(hex: hex) { return c }
        if let idx = ws.colorIndex { return Self.folderColor(idx) }
        return Self.folderColor(1)
    }
    /// The workspace's emoji icon (chosen, or a stable default).
    private func wsIcon(_ ws: Workspace) -> String {
        if let i = ws.icon, !i.isEmpty { return i }
        let n = Self.defaultWorkspaceIcons
        return n[abs(ws.id.uuidString.hashValue) % n.count]
    }

    /// Tint the sidebar + window background with the active workspace's colour — the visual
    /// "where am I" cue, extending under the traffic-light bar and around the floating card.
    private func applyWorkspaceTint() {
        guard let ws = workspaces.first(where: { $0.id == activeWorkspaceId }) else { return }
        let base = NSColor.underPageBackgroundColor
        let tint = (base.blended(withFraction: 0.20, of: wsColor(ws)) ?? base).cgColor
        sidebar.layer?.backgroundColor = tint
        window.contentView?.layer?.backgroundColor = tint
    }

    /// A quick crossfade when switching workspaces (sidebar tint + web card swap).
    private func animateWorkspaceSwitch() {
        for layer in [sidebar.layer, webContainer.layer, window.contentView?.layer] {
            let t = CATransition(); t.type = .fade; t.duration = 0.22
            layer?.add(t, forKey: "wsSwitch")
        }
    }

    /// Rebuild the workspace switcher: one emoji chip per workspace + a "+" to add one.
    private func rebuildWorkspaceBar() {
        applyWorkspaceTint()
        workspaceBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for ws in workspaces { workspaceBar.addArrangedSubview(makeWorkspacePill(ws)) }
        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New workspace")!,
                           target: self, action: #selector(addWorkspace))
        add.isBordered = false
        add.contentTintColor = .secondaryLabelColor
        add.translatesAutoresizingMaskIntoConstraints = false
        add.widthAnchor.constraint(equalToConstant: 26).isActive = true
        add.heightAnchor.constraint(equalToConstant: 26).isActive = true
        add.setContentHuggingPriority(.required, for: .horizontal)
        workspaceBar.addArrangedSubview(add)
    }

    /// An emoji-only workspace chip, sized to the icon; the active one is ringed in its colour.
    private func makeWorkspacePill(_ ws: Workspace) -> NSView {
        let active = ws.id == activeWorkspaceId
        let color = wsColor(ws)
        let pill = TabChipView()
        pill.onSelect = { [weak self] in self?.switchWorkspace(to: ws.id) }
        pill.menu = workspaceContextMenu(ws.id)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.widthAnchor.constraint(equalToConstant: 30).isActive = true
        pill.heightAnchor.constraint(equalToConstant: 30).isActive = true
        if active {
            pill.layer?.backgroundColor = color.withAlphaComponent(0.28).cgColor
            pill.layer?.borderWidth = 2
            pill.layer?.borderColor = color.cgColor
        } else {
            pill.layer?.backgroundColor = NSColor.clear.cgColor
        }

        let label = NSTextField(labelWithString: wsIcon(ws))
        label.font = .systemFont(ofSize: 15)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        pill.toolTip = ws.name
        pill.onHover = { [weak self] inside in self?.showWorkspaceHover(inside ? ws.id : nil) }
        return pill
    }

    /// Show the hovered workspace's number + name just above the switcher.
    private func showWorkspaceHover(_ id: UUID?) {
        guard let id, let idx = workspaceIndex(id) else { workspaceHoverLabel.isHidden = true; return }
        workspaceHoverLabel.stringValue = "⌃\(idx + 1)  ·  \(workspaces[idx].name)"
        workspaceHoverLabel.isHidden = false
    }

    private func switchWorkspace(to wid: UUID) {
        guard wid != activeWorkspaceId, workspaces.contains(where: { $0.id == wid }) else { return }
        lastActiveTabId[activeWorkspaceId] = activeTab.id
        activeWorkspaceId = wid
        animateWorkspaceSwitch()
        if let remembered = lastActiveTabId[wid], let i = tabIndex(id: remembered), tabs[i].workspaceId == wid {
            activeIndex = i
        } else if let i = tabs.firstIndex(where: { $0.workspaceId == wid }) {
            activeIndex = i
        } else {
            let t = makeTab(); t.workspaceId = wid; tabs.append(t)
            activeIndex = tabs.count - 1
            loadLanding(t)
        }
        activeTab.ensureLoaded()
        showActiveWebView(); rebuildTabBar(); persist()
    }

    @objc private func addWorkspace() {
        guard let name = promptForText(title: "New Workspace", message: "Name this workspace:", initial: "Space")
        else { return }
        var ws = Workspace(name: name)
        if let icon = promptForEmoji(initial: "") { ws.icon = icon }
        ws.colorHex = Self.folderColor(workspaces.count % Folder.palette.count).toHex
        workspaces.append(ws)
        switchWorkspace(to: ws.id) // spawns a landing tab in it + persists
    }

    private func workspaceContextMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu()
        func item(_ t: String, _ a: Selector) -> NSMenuItem {
            let m = NSMenuItem(title: t, action: a, keyEquivalent: ""); m.target = self
            m.representedObject = id.uuidString; return m
        }
        menu.addItem(item("Rename Workspace…", #selector(renameWorkspace(_:))))
        menu.addItem(item("Change Icon…", #selector(changeWorkspaceIcon(_:))))
        menu.addItem(item("Background Colour…", #selector(pickWorkspaceColor(_:))))
        menu.addItem(.separator())
        let del = item("Delete Workspace", #selector(deleteWorkspace(_:)))
        if workspaces.count <= 1 { del.action = nil } // keep at least one workspace
        menu.addItem(del)
        return menu
    }

    @objc private func renameWorkspace(_ s: NSMenuItem) {
        guard let id = (s.representedObject as? String).flatMap(UUID.init), let i = workspaceIndex(id) else { return }
        guard let name = promptForText(title: "Rename Workspace", message: "Workspace name:", initial: workspaces[i].name)
        else { return }
        workspaces[i].name = name; rebuildWorkspaceBar(); persist()
    }

    @objc private func changeWorkspaceIcon(_ s: NSMenuItem) {
        guard let id = (s.representedObject as? String).flatMap(UUID.init), let i = workspaceIndex(id) else { return }
        guard let icon = promptForEmoji(initial: workspaces[i].icon ?? "") else { return }
        workspaces[i].icon = icon
        rebuildWorkspaceBar(); persist()
    }

    /// Live background-colour picker for a workspace (full NSColorPanel).
    @objc private func pickWorkspaceColor(_ s: NSMenuItem) {
        colorPickWorkspace = (s.representedObject as? String).flatMap(UUID.init)
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(workspaceColorChanged(_:)))
        if let id = colorPickWorkspace, let i = workspaceIndex(id) { panel.color = wsColor(workspaces[i]) }
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func workspaceColorChanged(_ panel: NSColorPanel) {
        guard let id = colorPickWorkspace, let i = workspaceIndex(id) else { return }
        workspaces[i].colorHex = panel.color.toHex
        rebuildTabBar(); persist() // live: retints sidebar + active chip
    }

    @objc private func deleteWorkspace(_ s: NSMenuItem) {
        guard workspaces.count > 1, let id = (s.representedObject as? String).flatMap(UUID.init),
              let i = workspaceIndex(id) else { return }
        let active = tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
        for t in tabs where t.workspaceId == id { t.stop() }
        tabs.removeAll { $0.workspaceId == id }
        folders.removeAll { $0.workspaceId == id }
        workspaces.remove(at: i)
        lastActiveTabId[id] = nil
        if activeWorkspaceId == id {
            activeWorkspaceId = workspaces[0].id
            if let ai = tabs.firstIndex(where: { $0.workspaceId == activeWorkspaceId }) {
                activeIndex = ai
            } else {
                let t = makeTab(); t.workspaceId = activeWorkspaceId; tabs.append(t)
                activeIndex = tabs.count - 1; loadLanding(t)
            }
            activeTab.ensureLoaded(); showActiveWebView()
        } else if let a = active, let ai = tabs.firstIndex(where: { $0 === a }) {
            activeIndex = ai
        } else {
            activeIndex = min(activeIndex, tabs.count - 1)
        }
        rebuildTabBar(); persist()
    }

    /// First tab id in a section (for placing header/edge drops sensibly), or nil.
    private func firstTabId(kind: TabKind, folderId: UUID?) -> Int? {
        tabs.first { $0.kind == kind && $0.folderId == folderId }?.id
    }

    /// The folder swatch as a solid colour (for the coloured header background).
    static func folderColor(_ index: Int) -> NSColor {
        let rgb = Folder.palette[min(index, Folder.palette.count - 1)].rgb
        return NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }
    /// Black or white, whichever reads better on the given colour.
    private static func contrastingText(_ c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = 0.299 * s.redComponent + 0.587 * s.greenComponent + 0.114 * s.blueComponent
        return l > 0.62 ? .black : .white
    }

    @objc private func renameFolder(_ s: NSMenuItem) {
        guard let id = (s.representedObject as? String).flatMap(UUID.init), let i = folderIndex(id) else { return }
        guard let name = promptForText(title: "Rename Folder", message: "Folder name:", initial: folders[i].name)
        else { return }
        folders[i].name = name
        rebuildTabBar(); persist()
    }

    @objc private func recolorFolder(_ s: NSMenuItem) {
        guard let id = (s.representedObject as? String).flatMap(UUID.init), let i = folderIndex(id) else { return }
        folders[i].colorIndex = s.tag
        rebuildTabBar(); persist()
    }

    @objc private func deleteFolder(_ s: NSMenuItem) {
        guard let id = (s.representedObject as? String).flatMap(UUID.init) else { return }
        for t in tabs where t.folderId == id { t.folderId = nil } // pins survive, ungrouped
        folders.removeAll { $0.id == id }
        rebuildTabBar(); persist()
    }

    /// Right-click menu for a folder header row.
    private func folderContextMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: "")
            m.target = self; m.representedObject = id.uuidString; return m
        }
        menu.addItem(item("Rename Folder…", #selector(renameFolder(_:))))
        let color = NSMenuItem(title: "Colour", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (idx, swatch) in Folder.palette.enumerated() {
            let m = NSMenuItem(title: swatch.name, action: #selector(recolorFolder(_:)), keyEquivalent: "")
            m.target = self; m.tag = idx; m.representedObject = id.uuidString
            m.image = Self.swatchImage(idx)
            if folderIndex(id).map({ folders[$0].colorIndex == idx }) == true { m.state = .on }
            sub.addItem(m)
        }
        color.submenu = sub
        menu.addItem(color)
        menu.addItem(.separator())
        menu.addItem(item("Delete Folder", #selector(deleteFolder(_:))))
        return menu
    }

    /// A small round colour swatch for the palette menu / folder header.
    private static func swatchImage(_ colorIndex: Int) -> NSImage {
        let rgb = Folder.palette[min(colorIndex, Folder.palette.count - 1)].rgb
        let size = NSSize(width: 12, height: 12)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()
        return img
    }

    /// Simple modal text prompt (folder name / rename). Returns nil on cancel/empty.
    private func promptForText(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Prompt for a single emoji, auto-opening the macOS emoji picker so the user picks
    /// one visually (they can also type one). Returns nil on cancel.
    private func promptForEmoji(initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Workspace Icon"
        alert.informativeText = "Pick an emoji from the picker (or type one), then click OK."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        field.stringValue = initial
        field.font = .systemFont(ofSize: 20)
        field.alignment = .center
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        // Open the system emoji picker once the modal loop is running.
        DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(field) }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.first.map(String.init)
    }

    @objc func closeActiveTab() { closeTab(activeIndex) }

    func closeTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        let active = activeTab
        let closingActive = tabs[index] === active
        tabs[index].stop()
        tabs.remove(at: index)
        if tabs.isEmpty { window.performClose(nil); return } // truly the last tab → close window
        // If the active workspace now has no tabs, spawn a fresh landing tab in it.
        if !tabs.contains(where: { $0.workspaceId == activeWorkspaceId }) {
            let t = makeTab(); t.workspaceId = activeWorkspaceId; tabs.append(t)
            activeIndex = tabs.count - 1
            showActiveWebView(); loadLanding(t); rebuildTabBar(); persist(); return
        }
        if closingActive {
            activeIndex = tabs.firstIndex { $0.workspaceId == activeWorkspaceId } ?? 0
        } else if let ai = tabs.firstIndex(where: { $0 === active }) {
            activeIndex = ai
        } else {
            activeIndex = min(activeIndex, tabs.count - 1)
        }
        showActiveWebView()
        rebuildTabBar()
        persist()
    }

    private func showActiveWebView() {
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        let web = activeWebView
        web.translatesAutoresizingMaskIntoConstraints = false
        web.wantsLayer = true
        web.layer?.cornerRadius = 10 // clip page content to the floating card's corners
        web.layer?.masksToBounds = true
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
        rebuildWorkspaceBar()
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Only the active workspace's tabs and folders are visible.
        let ws = activeWorkspaceId
        let favs = tabs.enumerated().filter { $0.element.kind == .favourite && $0.element.workspaceId == ws }
        let pins = tabs.enumerated().filter { $0.element.kind == .pinned && $0.element.workspaceId == ws }
        let regs = tabs.enumerated().filter { $0.element.kind == .regular && $0.element.workspaceId == ws }
        let wsFolders = folders.filter { $0.workspaceId == ws }

        if !favs.isEmpty { tabStack.addArrangedSubview(favouritesRow(favs)) }

        // Ungrouped pinned tabs first, then each folder (header + its members when open).
        for (i, tab) in pins where tab.folderId == nil {
            tabStack.addArrangedSubview(makeTabChip(tab, index: i, active: i == activeIndex))
        }
        for folder in wsFolders {
            let members = pins.filter { $0.element.folderId == folder.id }
            tabStack.addArrangedSubview(folderHeaderRow(folder, count: members.count))
            if !folder.collapsed {
                for (i, tab) in members {
                    let chip = makeTabChip(tab, index: i, active: i == activeIndex, indented: true)
                    tabStack.addArrangedSubview(indentWrap(chip, by: 16))
                }
            }
        }

        if !favs.isEmpty || !pins.isEmpty || !wsFolders.isEmpty { tabStack.addArrangedSubview(separatorLine()) }
        for (i, tab) in regs { tabStack.addArrangedSubview(makeTabChip(tab, index: i, active: i == activeIndex)) }
        tabStack.addArrangedSubview(newTabRow())
    }

    /// Wrap an indented chip so it sits inset under a folder header while the row still
    /// spans the sidebar width (keeps the leading-aligned stack tidy).
    private func indentWrap(_ chip: NSView, by inset: CGFloat) -> NSView {
        let c = NSView()
        c.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(chip)
        NSLayoutConstraint.activate([
            c.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16),
            chip.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: inset),
            chip.topAnchor.constraint(equalTo: c.topAnchor),
            chip.bottomAnchor.constraint(equalTo: c.bottomAnchor),
        ])
        return c
    }

    /// A folder header: fully tinted with the folder's colour — disclosure chevron +
    /// name + member count. Click toggles; right-click = rename/colour/delete; a drop
    /// target for moving tabs in.
    private func folderHeaderRow(_ folder: Folder, count: Int) -> NSView {
        let bg = Self.folderColor(folder.colorIndex)
        let fg = Self.contrastingText(bg)
        let row = TabChipView()
        row.onSelect = { [weak self] in self?.toggleFolder(id: folder.id) }
        row.menu = folderContextMenu(folder.id)
        row.dragFolder = folder.id // drag the header to reorder folders
        row.onDrop = { [weak self] payload, before in
            guard let self else { return }
            switch payload {
            case .tab(let id): // drop a tab onto the header → into this folder (at top)
                self.moveTab(id, kind: .pinned, folderId: folder.id,
                             nextTo: self.firstTabId(kind: .pinned, folderId: folder.id), before: true)
            case .folder(let fid): // drop a folder onto the header → reorder folders
                self.moveFolder(fid, nextTo: folder.id, before: before)
            }
        }
        row.wantsLayer = true
        row.layer?.cornerRadius = 7
        row.layer?.backgroundColor = bg.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16).isActive = true
        row.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let chevron = NSImageView(image: NSImage(systemSymbolName: folder.collapsed ? "chevron.right" : "chevron.down",
                                                 accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))!)
        chevron.contentTintColor = fg
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: folder.name)
        name.font = .systemFont(ofSize: 11, weight: .semibold)
        name.textColor = fg
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSTextField(labelWithString: "\(count)")
        badge.font = .systemFont(ofSize: 10, weight: .medium)
        badge.textColor = fg.withAlphaComponent(0.75)
        badge.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(chevron); row.addSubview(name); row.addSubview(badge)
        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 9),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            name.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 7),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            badge.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func toggleFolder(id: UUID) {
        guard let i = folderIndex(id) else { return }
        folders[i].collapsed.toggle()
        rebuildTabBar(); persist()
    }

    private func newTabRow() -> NSView {
        // A drop here moves the dragged tab to the regular section (at the end) — the way
        // to pull a tab out of favourites/pins/folders when no regular tab is around.
        let row = TabChipView()
        row.onDrop = { [weak self] payload, _ in
            guard let self, case let .tab(id) = payload else { return }
            self.moveTab(id, kind: .regular, folderId: nil, nextTo: nil, before: false)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16).isActive = true
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let plus = NSButton(title: " New Tab",
                            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")!,
                            target: self, action: #selector(newTab))
        plus.imagePosition = .imageLeading
        plus.isBordered = false
        plus.font = .systemFont(ofSize: 12)
        plus.contentTintColor = .secondaryLabelColor
        plus.alignment = .left
        plus.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(plus)
        NSLayoutConstraint.activate([
            plus.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            plus.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            plus.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
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
        configureDrag(icon, tab: tab, horizontal: true) // reorder favourites by x
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
        if let fav = tab.favicon {
            // Show the site's own favicon, filling the tile (clipped to the rounded corners).
            // Neutral tile behind it so transparent icons don't pick up the avatar colour.
            icon.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            icon.layer?.masksToBounds = true
            let iv = NSImageView(image: fav)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            icon.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: icon.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: icon.trailingAnchor),
                iv.topAnchor.constraint(equalTo: icon.topAnchor),
                iv.bottomAnchor.constraint(equalTo: icon.bottomAnchor),
            ])
        } else {
            // Fallback: coloured letter avatar (until the favicon loads).
            let letter = NSTextField(labelWithString: tab.avatarLetter)
            letter.font = .systemFont(ofSize: 16, weight: .semibold)
            letter.textColor = .white
            letter.translatesAutoresizingMaskIntoConstraints = false
            icon.addSubview(letter)
            NSLayoutConstraint.activate([
                letter.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
                letter.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            ])
        }
        icon.toolTip = tab.title
        return icon
    }

    /// One tab row: title (left) + `×` (right) INSIDE a single full-width, clickable pill.
    /// `indented` insets it under a folder header.
    private func makeTabChip(_ tab: BrowserTab, index: Int, active: Bool, indented: Bool = false) -> NSView {
        let chip = TabChipView()
        chip.index = index
        chip.onSelect = { [weak self] in self?.selectTab(index) }
        chip.menu = tabContextMenu(index) // right-click: pin / favourite / close
        configureDrag(chip, tab: tab)      // drag into/out of folders
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 7
        chip.layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
            : NSColor.clear.cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false
        let inset: CGFloat = indented ? 16 : 0
        chip.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16 - inset).isActive = true
        chip.heightAnchor.constraint(equalToConstant: 32).isActive = true

        // Favicon (or a globe placeholder) in front of the title.
        let fav = NSImageView()
        fav.imageScaling = .scaleProportionallyDown
        fav.wantsLayer = true
        fav.layer?.cornerRadius = 3
        fav.layer?.masksToBounds = true
        fav.translatesAutoresizingMaskIntoConstraints = false
        if let icon = tab.favicon {
            fav.image = icon
        } else {
            fav.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
            fav.contentTintColor = .tertiaryLabelColor
        }

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

        chip.addSubview(fav); chip.addSubview(title); chip.addSubview(close)
        NSLayoutConstraint.activate([
            fav.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 9),
            fav.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            fav.widthAnchor.constraint(equalToConstant: 16),
            fav.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: fav.trailingAnchor, constant: 7),
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
        // Workspace switcher — a row of emoji chips pinned to the BOTTOM of the sidebar.
        workspaceBar.orientation = .horizontal
        workspaceBar.spacing = 6
        workspaceBar.alignment = .centerY
        workspaceBar.distribution = .fill
        workspaceBar.translatesAutoresizingMaskIntoConstraints = false

        workspaceHoverLabel.font = .systemFont(ofSize: 11, weight: .medium)
        workspaceHoverLabel.textColor = .secondaryLabelColor
        workspaceHoverLabel.lineBreakMode = .byTruncatingTail
        workspaceHoverLabel.isHidden = true
        workspaceHoverLabel.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(navRow)
        sidebar.addSubview(addressField) // Arc-style: URL bar in the sidebar, under nav
        sidebar.addSubview(workspaceBar)
        sidebar.addSubview(workspaceHoverLabel)
        sidebar.addSubview(tabStack)
        NSLayoutConstraint.activate([
            navRow.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 6),
            navRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 88), // clear of the traffic lights
            addressField.topAnchor.constraint(equalTo: navRow.bottomAnchor, constant: 10),
            addressField.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            addressField.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16),
            tabStack.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 12),
            tabStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            tabStack.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16),
            workspaceBar.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            workspaceBar.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -10),
            workspaceBar.widthAnchor.constraint(lessThanOrEqualToConstant: Self.sidebarWidth - 16),
            workspaceHoverLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            workspaceHoverLabel.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -8),
            workspaceHoverLabel.bottomAnchor.constraint(equalTo: workspaceBar.topAnchor, constant: -5),
            tabStack.bottomAnchor.constraint(lessThanOrEqualTo: workspaceHoverLabel.topAnchor, constant: -4),
        ])

        // Right area: the web content as a rounded card floating on the tinted background.
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.wantsLayer = true
        webContainer.layer?.cornerRadius = 10
        webContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        webContainer.layer?.masksToBounds = false
        webContainer.shadow = NSShadow()
        webContainer.layer?.shadowColor = NSColor.black.cgColor
        webContainer.layer?.shadowOpacity = 0.18
        webContainer.layer?.shadowRadius = 9
        webContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)

        // Sidebar can float ABOVE the web card (overlay on peek). The shadow + rounded
        // corners are toggled on only while floating so, when docked, it blends seamlessly
        // with the tinted background.
        sidebar.layer?.masksToBounds = false
        sidebar.shadow = NSShadow()
        sidebar.layer?.shadowColor = NSColor.black.cgColor
        sidebar.layer?.shadowRadius = 12
        sidebar.layer?.shadowOffset = CGSize(width: 3, height: 0)
        sidebar.layer?.shadowOpacity = 0 // docked by default

        let content = NSView()
        content.wantsLayer = true // holds the workspace tint behind the floating card
        content.addSubview(webContainer)
        content.addSubview(sidebar)        // above the web card
        window.contentView = content

        sidebarLeadingConstraint = sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 0)
        webLeadingDocked = webContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: Self.webCardInset)
        webLeadingFull = webContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.webCardInset)
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            sidebarLeadingConstraint,
            webContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.webCardTopInset),
            webContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.webCardInset),
            webLeadingDocked, // active while pinned open (the default)
            webContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.webCardInset),
        ])
        // Peek: leaving the floating sidebar slides it back (only while collapsed).
        sidebar.onExited = { [weak self] in self?.closePeek() }
        rebuildTabBar()
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        window.acceptsMouseMovedEvents = true
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            self?.handleMouseMoved(e); return e
        }
    }

    /// While collapsed, reveal the sidebar when the cursor reaches the left edge.
    private func handleMouseMoved(_ e: NSEvent) {
        guard !sidebarOpen, !peeking, let content = window.contentView else { return }
        let x = content.convert(e.locationInWindow, from: nil).x
        if x <= 4 { openPeek() }
    }

    /// Show/hide the native traffic lights — they belong to the sidebar, so they vanish
    /// when it's collapsed and reappear on peek/open.
    private func updateTrafficLights() {
        let hidden = !(sidebarOpen || peeking)
        for t: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(t)?.isHidden = hidden
        }
    }

    /// Round the corners + cast a shadow only while the sidebar is a floating overlay.
    private func setSidebarFloating(_ floating: Bool) {
        sidebar.layer?.cornerRadius = floating ? 12 : 0
        sidebar.layer?.shadowOpacity = floating ? 0.22 : 0
    }

    /// Hover-peek: while collapsed, sliding the cursor to the left edge reveals the sidebar
    /// as an overlay; moving off it slides it back.
    private func openPeek() {
        guard !sidebarOpen, !peeking else { return }
        peeking = true
        setSidebarFloating(true) // rounded + shadowed while revealed
        updateTrafficLights()
        slideSidebar(to: 0)
    }
    private func closePeek() {
        guard peeking else { return }
        peeking = false
        slideSidebar(to: -Self.sidebarWidth) { [weak self] in self?.updateTrafficLights() }
    }
    private func slideSidebar(to constant: CGFloat, then: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            sidebarLeadingConstraint.animator().constant = constant
            window.contentView?.layoutSubtreeIfNeeded()
        }, completionHandler: then)
    }

    @objc private func toggleSidebar() {
        sidebarOpen.toggle()
        peeking = false
        setSidebarFloating(false) // docked (or collapsed): flush + no shadow
        webLeadingDocked.isActive = sidebarOpen   // docked: web sits beside the sidebar
        webLeadingFull.isActive = !sidebarOpen     // collapsed: web fills the width
        if sidebarOpen { updateTrafficLights() }   // reveal immediately when opening
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            sidebarLeadingConstraint.animator().constant = sidebarOpen ? 0 : -Self.sidebarWidth
            window.contentView?.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            self?.updateTrafficLights() // hide after the collapse finishes
        })
    }

    private func configureButton(_ b: NSButton, symbol: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        b.isBordered = false                 // no bezel — crisp symbol on the tinted bar
        b.contentTintColor = .labelColor      // high-contrast (adapts light/dark), not accent blue
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Control+Number → switch to workspace N (Arc-style).
            if flags == .control, let ch = e.charactersIgnoringModifiers, let n = Int(ch), n >= 1 {
                if n <= self.workspaces.count { self.switchWorkspace(to: self.workspaces[n - 1].id) }
                return nil
            }
            guard flags.contains(.command) else { return e }
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
