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
    /// Per-profile history (isolated so autocomplete/suggestions don't leak across profiles).
    private var historyStores: [UUID: HistoryStore] = [:]
    /// Recently closed regular tabs (for Cmd+Shift+T), most-recent last.
    private var closedTabs: [SavedTab] = []
    private var palette: CommandPalette?
    private let askChat = AskChatView()
    private var askTask: Task<Void, Never>?
    private let notificationStore = NotificationStore()
    private let notificationsView = NotificationsView()
    private let remindersTool = RemindersTool()
    private var quickLooks: [QuickLookWindow] = []
    private var nextQuickLookId = 0
    private var taskManager: TaskManagerWindow?
    /// Task Manager responsiveness tracking: which tabs answered a JS ping, and any outstanding ping.
    private var tabResponsive: [Int: Bool] = [:]
    private var tabPingPending: [Int: Date] = [:]
    private var peek: PeekOverlay?
    private var nextPeekId = 0
    private var previewPopover: NSPopover?
    private var previewInjector: InjectionCoordinator?
    private var previewShowWork: DispatchWorkItem?
    private var previewCloseWork: DispatchWorkItem?
    private var skipAddressComplete = false // suppress autocomplete right after a delete
    private var miniPlayer: MiniPlayerWindow?
    private var miniTabId: Int?
    private var currentToast: NSView?
    private var toastDismiss: DispatchWorkItem?
    private var toastShareItems: [Any] = []
    private var toastPinned = false // held open while hovered or while the share sheet is up
    /// Pinned-tab folders (collapsible, renamable, colourable).
    private var folders: [Folder] = []
    /// Workspaces (each owns its favourites / pins / folders / regular tabs).
    private var workspaces: [Workspace] = []
    private var activeWorkspaceId = UUID()
    /// Profiles (separate cookie/login jars). The default profile uses the shared store.
    private var profiles: [Profile] = []
    private var defaultProfileId = UUID()
    private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    /// Air Traffic Control link-routing rules (host → workspace).
    private var routingRules: [RoutingRule] = []
    /// Remembers the last-active tab id per workspace (restored on switch).
    private var lastActiveTabId: [UUID: Int] = [:]
    private let workspaceBar = NSStackView()
    private let libraryButton = HoverIconButton()
    private let downloadStore = DownloadStore()
    private var libraryPane: LibraryPane?
    /// Floating name shown while hovering a workspace chip.
    private let workspaceHoverLabel = NSTextField(labelWithString: "")
    /// Workspace currently targeted by the live NSColorPanel.
    private var colorPickWorkspace: UUID?
    private var activeTab: BrowserTab { tabs[activeIndex] }
    private var activeWebView: WKWebView { activeTab.webView }
    /// Tab ids shown in the content area — one (normal) or 2–4 (split view).
    private var visibleTabIds: [Int] = []

    // Chrome
    private let addressField = NSTextField()
    private let backButton = HoverIconButton()
    private let forwardButton = HoverIconButton()
    private let reloadButton = HoverIconButton()
    private let settingsButton = HoverIconButton()
    private let shieldButton = HoverIconButton()
    private let translateButton = HoverIconButton()
    private let shareButton = HoverIconButton()
    /// Browser extensions: the controller delegate (maps Muninn tabs/windows) + the toolbar of
    /// per-extension action buttons under the address field.
    let extensionBridge = ExtensionBridge()
    private let extensionBar = NSStackView()
    private var extActionButtons: [NSButton: WKWebExtensionContext] = [:]
    private var lastNotifiedActiveTabId = -1
    private let shields = ShieldsManager.shared
    private let sidebar = HoverView()
    private let tabStack = NSStackView()
    /// Slide offset of the sidebar (0 = shown, -sidebarWidth = tucked off-screen left).
    private var sidebarLeadingConstraint: NSLayoutConstraint!
    /// Web card leading pinned to the sidebar (docked) vs the window edge (collapsed/peek).
    private var webLeadingDocked: NSLayoutConstraint!
    private var webLeadingFull: NSLayoutConstraint!
    private var sidebarOpen = true  // pinned-open
    private var peeking = false     // temporarily revealed by hovering the left edge
    private let toggleButton = HoverIconButton()
    // Right-side Tools sidebar (hosts the Live Calendar).
    private let toolsSidebar = ToolsSidebar()
    private let toolsButton = HoverIconButton()
    private var toolsOpen = false
    private var webTrailingCollapsed: NSLayoutConstraint!
    private var webTrailingWithTools: NSLayoutConstraint!
    private static let defaultToolsWidth: CGFloat = 280
    /// User-resizable pane widths (persisted). Clamped to sensible bounds.
    private var toolsWidth: CGFloat = 280
    private var toolsWidthConstraint: NSLayoutConstraint!
    private static let toolsWidthRange: ClosedRange<CGFloat> = 220...520
    private let sidebarSplitter = SplitterHandle()
    private let toolsSplitter = SplitterHandle()
    // Live Calendar (first Tools-sidebar tool).
    private var liveCalendars: [LiveCalendar] = []
    private let calendarFeed = CalendarFeed()
    private let liveWidget = LiveCalendarWidget()
    private var currentOccurrence: Occurrence?
    private var calendarTick: Timer?
    private var mouseMonitor: Any?
    private var archiveTimer: Timer?
    private static let defaultSidebarWidth: CGFloat = 284
    /// User-resizable left-sidebar width (persisted). Clamped to sensible bounds.
    private var sidebarWidth: CGFloat = 284
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private static let sidebarWidthRange: ClosedRange<CGFloat> = 248...460
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

        // Profiles — ensure a default; it keeps the shared store so existing logins survive.
        profiles = saved.profiles.isEmpty ? [Profile(name: "Personal", colorIndex: 1)] : saved.profiles
        defaultProfileId = profiles[0].id
        let profileIds = Set(profiles.map { $0.id })
        routingRules = saved.routingRules
        liveCalendars = saved.liveCalendars
        // Restore user-resized pane widths (clamped), else use the defaults.
        sidebarWidth = saved.sidebarWidth.map { min(max(CGFloat($0), Self.sidebarWidthRange.lowerBound), Self.sidebarWidthRange.upperBound) } ?? Self.defaultSidebarWidth
        toolsWidth = saved.toolsWidth.map { min(max(CGFloat($0), Self.toolsWidthRange.lowerBound), Self.toolsWidthRange.upperBound) } ?? Self.defaultToolsWidth

        // Folders — assign any pre-workspaces folder to the default workspace.
        folders = saved.folders.map { var f = $0; if f.workspaceId == nil { f.workspaceId = defaultWs }; return f }
        let folderIds = Set(folders.map { $0.id })
        let wsIds = Set(workspaces.map { $0.id })
        // Drop dangling workspace profile refs.
        workspaces = workspaces.map { var w = $0; if let p = w.profileId, !profileIds.contains(p) { w.profileId = nil }; return w }

        // First (session) regular tab in the active workspace, then restore saved tabs.
        tabs.append(makeTab(workspaceId: activeWorkspaceId))
        for s in saved.tabs {
            guard let url = URL(string: s.url) else { continue }
            let wid = s.workspaceId.flatMap(UUID.init).flatMap { wsIds.contains($0) ? $0 : nil } ?? defaultWs
            let tab = makeTab(workspaceId: wid)
            tab.kind = s.kind
            tab.pendingURL = url
            tab.homeURL = url // anchored site for Peek (restored pinned/favourite)
            tab.setInitialTitle(s.title)
            tab.customTitle = s.customTitle
            tab.setInitialFavicon(base64: s.faviconBase64)
            if let fid = s.folderId.flatMap(UUID.init), folderIds.contains(fid) { tab.folderId = fid }
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
        if saved.toolsSidebarOpen { setToolsOpen(true, animated: false) } // restore Tools sidebar
        showActiveWebView()

        loadLanding(activeTab) // default new-tab page (auth-fork paths override in present())
        window.center()
    }

    func present() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
        installMouseMonitor()
        PageTranslator.shared.attach(to: window)   // offscreen SwiftUI host for on-device translation
        // Auto-Archive sweep every few minutes (also runs on each tab switch).
        archiveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.archiveStaleTabs()
                self?.pruneNotifications()
            }
        }
        startLiveCalendar()
        // Shields: recompile on change → re-apply to all tabs + refresh the icon; compile now.
        shields.onChange = { [weak self] in
            guard let self else { return }
            self.applyShieldsToAllTabs(); self.updateShieldIcon()
        }
        shields.rebuild()
        updateShieldIcon()
        // Browser extensions: point the controller at this window, then load enabled extensions.
        extensionBridge.host = self
        ExtensionManager.shared.controller.delegate = extensionBridge
        ExtensionManager.shared.onChange = { [weak self] in self?.rebuildExtensionToolbar() }
        ExtensionManager.shared.loadEnabled()
        rebuildExtensionToolbar()
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

    /// Create a tab in `workspaceId` (defaults to the active workspace), backed by that
    /// workspace's profile data store (its cookie/login jar).
    private func makeTab(workspaceId: UUID? = nil) -> BrowserTab {
        let wid = workspaceId ?? activeWorkspaceId
        let id = nextTabId; nextTabId += 1
        let tab = BrowserTab(id: id, broker: broker, dataStore: dataStore(forWorkspace: wid))
        tab.workspaceId = wid
        configureTab(tab)
        return tab
    }

    /// Wire a tab's callbacks (used by `makeTab` and when re-creating tabs on a profile change).
    private func configureTab(_ tab: BrowserTab) {
        tab.onChange = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.rebuildTabBar()
            if tab === self.activeTab {
                self.updateChrome()
                if let url = tab.webView.url {
                    self.storeForkStateIfPresent(url)
                    self.currentHistory.record(url: url, title: tab.title)
                }
            }
        }
        // Peek: intercept cross-site link clicks in an anchored (pinned/favourite) tab.
        tab.injector.onNavigationAction = { [weak self, weak tab] action in
            guard let self, let tab else { return .allow }
            return self.decideNavigation(for: tab, action)
        }
        // Mini Player: track media playback so switching away can pop it out.
        tab.injector.onMediaState = { [weak self, weak tab] playing in
            guard let self, let tab else { return }
            tab.isPlayingMedia = playing
            if tab.id == self.miniTabId { self.miniPlayer?.setPlaying(playing) }
        }
        // Downloads land in the tab's profile download folder.
        tab.injector.downloadFolder = { [weak self, weak tab] in
            let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            guard let self, let wid = tab?.workspaceId else { return fallback }
            let pid = self.workspaces.first { $0.id == wid }?.profileId ?? self.defaultProfileId
            return self.profiles.first { $0.id == pid }?.downloadFolder ?? fallback
        }
        // Developer Mode: right-click "View Page Source" → a new tab showing the HTML.
        tab.injector.onViewSource = { [weak self] wv in self?.viewSource(of: wv) }
        // Middle-click a link → open it in a background tab (current tab stays put).
        tab.injector.onMiddleClickLink = { [weak self] url in self?.openInBackgroundTab(url) }
        // Shields: per-site JavaScript decision + apply the content-rule list to this tab.
        tab.injector.onDecideJavaScript = { url in ShieldsManager.shared.javaScriptAllowed(for: url) }
        applyShields(to: tab)
        // Record finished downloads for the Library + play the "drop into Library" animation.
        tab.injector.onDownloadFinished = { [weak self] dest, source in
            self?.downloadStore.add(path: dest, source: source)
            self?.flyToLibrary(icon: NSWorkspace.shared.icon(forFile: dest.path))
        }
        // target="_blank" / window.open: Peek from a pinned tab (cross-site), else a new tab.
        tab.injector.onCreateWebView = { [weak self, weak tab] action in
            guard let self, let tab, let url = action.request.url, url.scheme?.hasPrefix("http") == true else { return }
            let peek = tab.kind != .regular && {
                if let home = tab.homeURL ?? tab.webView.url, let hh = home.host, let nh = url.host { return hh != nh }
                return false
            }()
            DispatchQueue.main.async { [weak self] in
                if peek { self?.showPeek(url) } else { self?.openInNewTab(url) }
            }
        }
    }

    /// A cross-site link click in a pinned/favourite tab opens a Peek instead of navigating
    /// the anchored tab away from its home.
    private func decideNavigation(for tab: BrowserTab, _ action: WKNavigationAction) -> WKNavigationActionPolicy {
        if let url = action.request.url, url.scheme?.hasPrefix("http") == true,
           action.targetFrame?.isMainFrame == true, shields.shieldsUp(for: url.host) {
            // Shields: debounce known bounce-trackers → jump straight to the destination.
            if shields.debounce, let dest = Debouncer.destination(for: url) {
                DispatchQueue.main.async { [weak self] in self?.loadCleaned(dest, in: tab) }
                return .cancel
            }
            // Shields: strip tracking query params, then re-load clean.
            if shields.stripQueryParams, let cleaned = QueryStripper.strip(url) {
                DispatchQueue.main.async { [weak self] in self?.loadCleaned(cleaned, in: tab) }
                return .cancel
            }
        }
        guard tab.kind != .regular,
              action.navigationType == .linkActivated,
              action.targetFrame?.isMainFrame == true,
              let url = action.request.url, url.scheme?.hasPrefix("http") == true,
              let home = tab.homeURL ?? tab.webView.url,
              let homeHost = home.host, let newHost = url.host, homeHost != newHost
        else { return .allow }
        // Defer the Peek to the next tick — creating a web view synchronously inside the
        // navigation-policy callback re-enters WebKit and crashes.
        DispatchQueue.main.async { [weak self] in self?.showPeek(url) }
        return .cancel
    }

    /// Load a query-stripped URL, preserving the Peek behaviour for pinned/favourite tabs.
    private func loadCleaned(_ url: URL, in tab: BrowserTab) {
        if tab.kind != .regular, let home = tab.homeURL ?? tab.webView.url,
           let hh = home.host, let nh = url.host, hh != nh {
            showPeek(url)
        } else {
            tab.load(url)
        }
    }

    // MARK: - Peek (link preview from pinned tabs)

    private func showPeek(_ url: URL) {
        let content = webContainer
        hidePeek()
        let p = PeekOverlay(broker: broker, id: nextPeekId); nextPeekId += 1
        p.onClose = { [weak self] in self?.hidePeek() }
        p.onPromote = { [weak self] u in self?.openInNewTab(u) }
        peek = p
        p.activate(in: content, url: url)
    }
    private func hidePeek() {
        peek?.tearDown()
        peek?.removeFromSuperview()
        peek = nil
    }

    // MARK: - Previews (glance a favourite site on hover)

    private func schedulePreview(for index: Int, from view: NSView) {
        previewCloseWork?.cancel()
        previewShowWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, view.window != nil else { return }
            self.showPreview(index, from: view)
        }
        previewShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private func scheduleClosePreview() {
        previewShowWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.closePreview() }
        previewCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    private func showPreview(_ index: Int, from view: NSView) {
        guard tabs.indices.contains(index),
              let url = tabs[index].currentURL ?? tabs[index].homeURL,
              url.scheme?.hasPrefix("http") == true else { return }
        previewPopover?.close()
        let inj = previewInjector ?? InjectionCoordinator(broker: broker, contextName: "preview")
        previewInjector = inj
        inj.load(url)
        let web = inj.webView!

        // A live, interactive preview. Hovering it keeps it open; leaving closes it.
        let container = HoverView(frame: NSRect(x: 0, y: 0, width: 480, height: 560))
        container.onEntered = { [weak self] in self?.previewCloseWork?.cancel() }
        container.onExited = { [weak self] in self?.scheduleClosePreview() }
        web.frame = container.bounds
        web.autoresizingMask = [.width, .height]
        web.wantsLayer = true; web.layer?.cornerRadius = 8; web.layer?.masksToBounds = true
        container.addSubview(web)

        let vc = NSViewController()
        vc.view = container
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.contentSize = NSSize(width: 480, height: 560)
        pop.behavior = .applicationDefined // dismissed by hover-out, not outside clicks
        pop.animates = true
        previewPopover = pop
        pop.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
    }
    private func closePreview() {
        previewShowWork?.cancel()
        previewPopover?.close()
        previewPopover = nil
        previewInjector?.webView?.stopLoading()
        if let blank = URL(string: "about:blank") { previewInjector?.load(blank) } // free the page
    }

    // MARK: - Mini Player (watch/listen while browsing)

    private static let mediaToggleJS = "(function(){var m=Array.prototype.find.call(document.querySelectorAll('video,audio'),function(x){return !x.ended;});if(!m)return;if(m.paused)m.play();else m.pause();})()"
    private static let mediaPauseJS = "(function(){Array.prototype.forEach.call(document.querySelectorAll('video,audio'),function(m){if(!m.paused)m.pause();});})()"
    /// Float the playing <video> fullscreen over a black overlay (reversible) so the Mini Player
    /// shows only the video, not the whole page.
    // Reparent the playing <video> into a fixed fullscreen wrapper at the document root (this
    // survives transformed/clipped ancestors like YouTube), size it with !important rules (so
    // the site's own inline sizing can't win — the video then scales with the window), and add
    // click-to-toggle with a centered icon flash.
    private static let videoOnlyEnterJS = """
    (function(){
      var vids=document.querySelectorAll('video');
      var v=Array.prototype.find.call(vids,function(x){return !x.paused;})||vids[0];
      if(!v||window.__muninnMiniVideo){return;}
      v.__muninnMini={parent:v.parentNode,next:v.nextSibling};
      window.__muninnMiniVideo=v;
      var st=document.createElement('style');st.id='__muninnMiniStyle';
      st.textContent=
        '#__muninnMiniWrap{position:fixed;top:0;left:0;width:100vw;height:100vh;margin:0;background:#000;z-index:2147483647;display:flex;align-items:center;justify-content:center;}'+
        '#__muninnMiniWrap video{width:100%!important;height:100%!important;max-width:100%!important;max-height:100%!important;object-fit:contain!important;background:#000!important;left:auto!important;top:auto!important;}'+
        '#__muninnMiniIcon{position:absolute;top:50%;left:50%;width:96px;height:96px;transform:translate(-50%,-50%);pointer-events:none;opacity:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.55);border-radius:50%;color:#fff;font:600 46px -apple-system,system-ui,Arial,sans-serif;line-height:1;}'+
        '@keyframes muninnPop{0%{opacity:0;transform:translate(-50%,-50%) scale(.6);}18%{opacity:1;transform:translate(-50%,-50%) scale(1);}100%{opacity:0;transform:translate(-50%,-50%) scale(1.4);}}'+
        'html{overflow:hidden!important;}';
      document.documentElement.appendChild(st);
      var wrap=document.createElement('div');wrap.id='__muninnMiniWrap';
      document.documentElement.appendChild(wrap);
      wrap.appendChild(v);
      var icon=document.createElement('div');icon.id='__muninnMiniIcon';wrap.appendChild(icon);
      window.__muninnToggle=function(){
        var vid=window.__muninnMiniVideo; if(!vid)return;
        var pausing=!vid.paused;
        if(vid.paused)vid.play();else vid.pause();
        icon.textContent=pausing?'⏸':'▶';
        icon.style.animation='none'; void icon.offsetWidth; icon.style.animation='muninnPop .55s ease-out';
      };
    })()
    """
    private static let videoOnlyExitJS = """
    (function(){
      var v=window.__muninnMiniVideo;
      if(v&&v.__muninnMini){
        var i=v.__muninnMini;
        if(i.parent){ if(i.next&&i.next.parentNode===i.parent)i.parent.insertBefore(v,i.next);else i.parent.appendChild(v); }
        delete v.__muninnMini;
      }
      window.__muninnMiniVideo=null; window.__muninnToggle=null;
      var wrap=document.getElementById('__muninnMiniWrap');if(wrap)wrap.remove();
      var st=document.getElementById('__muninnMiniStyle');if(st)st.remove();
      document.documentElement.style.overflow='';
    })()
    """

    /// Pop a still-playing tab out into the Mini Player (borrows its web view, shows just the video).
    private func startMiniPlayer(_ tab: BrowserTab) {
        stopMiniPlayer()
        let mp = MiniPlayerWindow()
        miniPlayer = mp; miniTabId = tab.id
        mp.attach(tab.webView)
        tab.webView.evaluateJavaScript(Self.videoOnlyEnterJS, completionHandler: nil)
        mp.setPlaying(tab.isPlayingMedia)
        mp.onTogglePlay = { [weak self] in self?.toggleMiniPlay() }
        mp.onReturn = { [weak self] in
            guard let self, let id = self.miniTabId, let i = self.tabIndex(id: id) else { return }
            self.selectTab(i)
        }
        mp.onClose = { [weak self] in self?.closeMiniPlayer(pause: true) }
        mp.present()
    }

    private func stopMiniPlayer() {
        if let id = miniTabId, let i = tabIndex(id: id) {
            tabs[i].webView.evaluateJavaScript(Self.videoOnlyExitJS, completionHandler: nil) // restore the page
        }
        miniPlayer?.teardown()
        miniPlayer = nil; miniTabId = nil
    }

    private func closeMiniPlayer(pause: Bool) {
        if pause, let id = miniTabId, let i = tabIndex(id: id) {
            tabs[i].webView.evaluateJavaScript(Self.mediaPauseJS, completionHandler: nil)
        }
        stopMiniPlayer()
    }

    private func toggleMiniPlay() {
        guard let id = miniTabId, let i = tabIndex(id: id) else { return }
        // Prefer the mini-mode toggle (shows the icon flash); fall back to a plain toggle.
        tabs[i].webView.evaluateJavaScript("window.__muninnToggle?(window.__muninnToggle(),1):0", completionHandler: nil)
    }

    @objc func newTab() {
        let outgoing = activeTab
        outgoing.lastActiveAt = Date()
        let tab = makeTab(); tab.workspaceId = activeWorkspaceId
        tabs.append(tab)
        extensionBridge.didOpen(tab)
        activeIndex = tabs.count - 1
        popOutIfPlaying(outgoing) // Cmd+T while a video plays → Mini Player
        showActiveWebView()
        rebuildTabBar()
        loadLanding(activeTab)
        animateTabOpen()
        window.makeFirstResponder(addressField)
    }

    /// Muninn's new-tab landing page: a search box (DuckDuckGo, or a typed URL) — a
    /// placeholder we can grow into a real start page later.
    private func loadLanding(_ tab: BrowserTab) {
        let hosts = suggestionsEnabled ? Array(currentHistory.rankedHosts().prefix(60)) : []
        let json = (try? JSONSerialization.data(withJSONObject: hosts))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let engine = currentSearchEngine
        let html = Self.landingHTML
            .replacingOccurrences(of: "__MUNINN_HOSTS__", with: json)
            .replacingOccurrences(of: "__MUNINN_SEARCH__", with: engine.searchBase)
            .replacingOccurrences(of: "__RAVEN_MASK_DATAURI__", with: Self.ravenMaskDataURI)
        tab.webView.loadHTMLString(html, baseURL: URL(string: engine.searchBase))
    }

    /// The icon's raven, extracted as a silhouette (white-on-transparent PNG), used as a faint
    /// CSS mask on the landing page so it tints with the theme. Traced from the app icon art.
    private static let ravenMaskDataURI = "data:image/png;base64,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"

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
      .raven-bg{position:fixed;inset:0;margin:auto;width:min(58vw,58vh);aspect-ratio:520/381;
        background:#1a1a2e;opacity:.05;z-index:-1;pointer-events:none;
        -webkit-mask:url(__RAVEN_MASK_DATAURI__) center/contain no-repeat;
        mask:url(__RAVEN_MASK_DATAURI__) center/contain no-repeat}
      @media (prefers-color-scheme: dark){
        body{background:#16161f;color:#e8e8f2}.sub{color:#8a8aa8}
        input{background:#22222e;border-color:#33334d;color:#fff;box-shadow:none}
        input:focus{border-color:#7777f8}
        .raven-bg{background:#e8e8f2;opacity:.07}
      }
    </style></head><body>
      <div class="raven-bg" aria-hidden="true"></div>
      <h1>Muninn</h1><div class="sub">Private. Native. Yours.</div>
      <form action="__MUNINN_SEARCH__" method="get" autocomplete="off">
        <input name="q" placeholder="Search or enter a URL" autofocus>
      </form>
      <script>
        var HOSTS = __MUNINN_HOSTS__;
        var input = document.querySelector('input');
        var skip = false;
        input.addEventListener('keydown', function (e) {
          if (e.key === 'Backspace' || e.key === 'Delete') { skip = true; }
          else if (e.key === 'Tab' || e.key === 'ArrowRight') {
            if (input.selectionStart !== input.selectionEnd) {
              e.preventDefault(); input.setSelectionRange(input.value.length, input.value.length);
            }
          }
        });
        input.addEventListener('input', function () {
          if (skip) { skip = false; return; }
          var v = input.value;
          if (!v || /\\s/.test(v) || input.selectionStart !== v.length) return;
          var q = v.toLowerCase();
          if (q.indexOf('https://') === 0) q = q.slice(8);
          else if (q.indexOf('http://') === 0) q = q.slice(7);
          if (q.indexOf('www.') === 0) q = q.slice(4);
          if (!q || q.indexOf('/') >= 0) return;
          for (var i = 0; i < HOSTS.length; i++) {
            var h = HOSTS[i];
            if (h.indexOf(q) === 0 && h !== q) {
              var completed = v + h.slice(q.length);
              input.value = completed; input.setSelectionRange(v.length, completed.length);
              break;
            }
          }
        });
        document.querySelector('form').addEventListener('submit', function (e) {
          var q = input.value.trim();
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
        // Returning to the mini'd tab reclaims its web view from the Mini Player.
        if tabs[index].id == miniTabId { stopMiniPlayer() }
        let outgoing = activeTab
        outgoing.lastActiveAt = Date() // it was in the foreground until now
        activeIndex = index
        tabs[index].lastActiveAt = Date()
        lastActiveTabId[activeWorkspaceId] = tabs[index].id
        tabs[index].ensureLoaded() // lazily load a restored favourite/pinned tab
        popOutIfPlaying(outgoing) // switching away from a still-playing tab → Mini Player
        showVisibleTabs() // shows the tab's split group, or the tab alone
        rebuildTabBar()
        archiveStaleTabs() // clean up idle tabs opportunistically
    }

    /// Auto-Archive: close regular, ungrouped tabs left idle past the configured interval
    /// (the active tab, pinned/favourites, split members, and the Mini Player tab are exempt).
    /// Archived tabs stay reopenable via Cmd+Shift+T and history.
    private func archiveStaleTabs() {
        guard let interval = currentAutoArchive.interval else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let activeId = tabs.indices.contains(activeIndex) ? tabs[activeIndex].id : -1
        let staleIds = tabs.filter {
            $0.kind == .regular && $0.splitGroupId == nil
                && $0.id != activeId && $0.id != miniTabId && $0.lastActiveAt < cutoff
        }.map { $0.id }
        for id in staleIds where tabIndex(id: id) != nil { closeTab(tabIndex(id: id)!) }
    }

    /// Pop the outgoing tab into the Mini Player if it's still playing media.
    private func popOutIfPlaying(_ outgoing: BrowserTab) {
        guard outgoing !== activeTab, outgoing.isPlayingMedia, outgoing.id != miniTabId else { return }
        startMiniPlayer(outgoing)
    }

    /// Persist favourites + pinned tabs, folders, and workspaces (regular tabs are session-only).
    private func persist() {
        // Drop empty folders that no pinned tab references (keeps state tidy).
        let used = Set(tabs.filter { $0.kind == .pinned }.compactMap { $0.folderId })
        folders.removeAll { !used.contains($0.id) }
        store.save(SidebarState(tabs: tabs.filter { $0.kind != .regular }.compactMap { $0.saved() },
                                folders: folders,
                                workspaces: workspaces,
                                activeWorkspace: activeWorkspaceId.uuidString,
                                profiles: profiles,
                                routingRules: routingRules,
                                toolsSidebarOpen: toolsOpen,
                                liveCalendars: liveCalendars,
                                sidebarWidth: Double(sidebarWidth),
                                toolsWidth: Double(toolsWidth)))
    }

    private func setKind(_ index: Int, _ kind: TabKind) {
        guard tabs.indices.contains(index) else { return }
        if tabs[index].splitGroupId != nil { removeFromSplit(index) } // leaving the regular section
        tabs[index].kind = kind
        // Anchor the tab to its current site for Peek; clear when it goes back to regular.
        tabs[index].homeURL = (kind == .regular) ? nil : (tabs[index].webView.url ?? tabs[index].currentURL)
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

        // Custom name — override the page title in the sidebar (content untouched).
        menu.addItem(item("Rename…", #selector(renameTab(_:))))
        if tabs[index].customTitle != nil { menu.addItem(item("Reset Name", #selector(resetTabName(_:)))) }

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

        // Split View (regular tabs).
        let tab = tabs[index]
        if tab.splitGroupId != nil {
            menu.addItem(item("Remove from Split View", #selector(removeFromSplitMenu(_:))))
        } else if tab.kind == .regular && index != activeIndex && activeTab.kind == .regular
                    && tab.workspaceId == activeWorkspaceId
                    && (activeTab.splitGroupId == nil || groupCount(activeTab.splitGroupId!) < 4) {
            menu.addItem(item("Add to Split View", #selector(addToSplitMenu(_:))))
        }

        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(closeTabMenu(_:))))
        return menu
    }

    // MARK: - rename tab

    @objc private func renameTab(_ s: NSMenuItem) {
        guard tabs.indices.contains(s.tag) else { return }
        let tab = tabs[s.tag]
        guard let name = promptForText(title: "Rename Tab", message: "Tab name:", initial: tab.displayTitle)
        else { return }
        tab.customTitle = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        rebuildTabBar(); persist()
    }

    @objc private func resetTabName(_ s: NSMenuItem) {
        guard tabs.indices.contains(s.tag) else { return }
        tabs[s.tag].customTitle = nil
        rebuildTabBar(); persist()
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
        // Regular (ungrouped) tabs support a center "drop onto" that forms a split.
        chip.dropSupportsOnto = tab.kind == .regular && tab.folderId == nil
        chip.onDrop = { [weak self, weak tab] payload, zone in
            guard let self, let tab, case let .tab(draggedId) = payload else { return }
            if zone == .onto {
                self.dropSplit(draggedId, onto: tab.id)
            } else {
                self.moveTab(draggedId, kind: tab.kind, folderId: tab.folderId, nextTo: tab.id, before: zone == .before)
            }
        }
    }

    /// Move a tab to a section (kind + optional folder) and position it next to `targetId`
    /// (or at the end when nil). Preserves the active tab across the reorder.
    private func moveTab(_ id: Int, kind: TabKind, folderId: UUID?, nextTo targetId: Int?, before: Bool) {
        guard id != targetId, let from = tabIndex(id: id) else { return }
        let active = activeTab
        let tab = tabs[from]
        // Reordering/moving a split member takes it out of the split.
        let leftSplit = tab.splitGroupId != nil
        if let gid = tab.splitGroupId {
            tab.splitGroupId = nil
            let remaining = tabs.enumerated().filter { $0.element.splitGroupId == gid }
            if remaining.count <= 1 { remaining.forEach { tabs[$0.offset].splitGroupId = nil } }
        }
        tabs.remove(at: from)
        tab.kind = kind
        tab.folderId = (kind == .pinned) ? folderId : nil
        var insertAt = tabs.count
        if let targetId, let t = tabIndex(id: targetId) { insertAt = before ? t : t + 1 }
        tabs.insert(tab, at: min(max(insertAt, 0), tabs.count))
        if let ai = tabs.firstIndex(where: { $0 === active }) { activeIndex = ai }
        if leftSplit { showVisibleTabs() }
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
    private func profileIndex(_ id: UUID) -> Int? { profiles.firstIndex { $0.id == id } }

    // MARK: - settings window data API

    private var settingsController: SettingsWindowController?

    @objc func openSettings() {
        let firstTime = settingsController == nil
        if firstTime { settingsController = SettingsWindowController(host: self) }
        if firstTime { settingsController?.window?.center() }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func settingsProfiles() -> [Profile] { profiles }
    var settingsDefaultProfileId: UUID { defaultProfileId }
    func settingsWorkspaceCount(for pid: UUID) -> Int {
        workspaces.filter { ($0.profileId ?? defaultProfileId) == pid }.count
    }
    func settingsAddProfile() -> Profile {
        let p = Profile(name: "New Profile", colorIndex: profiles.count % Folder.palette.count)
        profiles.append(p); persist(); return p
    }
    func settingsRenameProfile(_ id: UUID, to name: String) {
        guard let i = profileIndex(id), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        profiles[i].name = name; rebuildWorkspaceBar(); persist()
    }
    /// Remove a profile (not the default): move its workspaces to the default profile, re-create
    /// their tabs, and wipe its history + website data. Returns false if it can't be removed.
    @discardableResult
    func settingsRemoveProfile(_ id: UUID) -> Bool {
        guard profiles.count > 1, id != defaultProfileId, let i = profileIndex(id) else { return false }
        let moved = workspaces.enumerated().filter { ($0.element.profileId ?? defaultProfileId) == id }.map { $0.offset }
        for wi in moved { workspaces[wi].profileId = defaultProfileId }
        profiles.remove(at: i)
        for wi in moved { reprofileWorkspace(workspaces[wi].id) }
        history(forProfile: id).clear(); historyStores[id] = nil
        dataStores[id] = nil
        WKWebsiteDataStore.remove(forIdentifier: id) { _ in }
        rebuildWorkspaceBar(); rebuildTabBar(); persist()
        return true
    }
    func settingsUpdateProfile(_ id: UUID, _ mutate: (inout Profile) -> Void) {
        guard let i = profileIndex(id) else { return }
        mutate(&profiles[i]); persist()
        if id == currentProfileId { archiveStaleTabs() }
    }
    var settingsWarnBeforeQuitting: Bool {
        get { AppSettings.warnBeforeQuitting }
        set { AppSettings.warnBeforeQuitting = newValue }
    }

    // MARK: - settings

    @objc private func showSettingsMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())

        let engineItem = NSMenuItem(title: "Search Engine", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for e in SearchEngine.allCases {
            let m = NSMenuItem(title: e.displayName, action: #selector(setSearchEngine(_:)), keyEquivalent: "")
            m.target = self; m.representedObject = e.rawValue
            if e == currentSearchEngine { m.state = .on }
            sub.addItem(m)
        }
        engineItem.submenu = sub
        menu.addItem(engineItem)

        let archiveItem = NSMenuItem(title: "Auto-Archive Tabs", action: nil, keyEquivalent: "")
        let asub = NSMenu()
        for a in AutoArchive.allCases {
            let m = NSMenuItem(title: a.displayName, action: #selector(setAutoArchive(_:)), keyEquivalent: "")
            m.target = self; m.representedObject = a.rawValue
            if a == currentAutoArchive { m.state = .on }
            asub.addItem(m)
        }
        archiveItem.submenu = asub
        menu.addItem(archiveItem)

        menu.addItem(.separator())
        let def = NSMenuItem(title: "Set as Default Browser…", action: #selector(makeDefaultBrowser), keyEquivalent: "")
        def.target = self; menu.addItem(def)
        let clear = NSMenuItem(title: "Clear This Profile’s Data…", action: #selector(clearProfileData), keyEquivalent: "")
        clear.target = self; menu.addItem(clear)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func setSearchEngine(_ s: NSMenuItem) {
        guard let e = (s.representedObject as? String).flatMap(SearchEngine.init(rawValue:)),
              let i = profileIndex(currentProfileId) else { return }
        profiles[i].searchEngineRaw = e.rawValue; persist()
    }

    @objc private func setAutoArchive(_ s: NSMenuItem) {
        guard let a = (s.representedObject as? String).flatMap(AutoArchive.init(rawValue:)),
              let i = profileIndex(currentProfileId) else { return }
        profiles[i].autoArchiveRaw = a.rawValue; persist()
        archiveStaleTabs()
    }

    @objc private func makeDefaultBrowser() {
        let ws = NSWorkspace.shared
        let bundleURL = Bundle.main.bundleURL
        ws.setDefaultApplication(at: bundleURL, toOpenURLsWithScheme: "https") { _ in }
        ws.setDefaultApplication(at: bundleURL, toOpenURLsWithScheme: "http") { error in
            Task { @MainActor in
                let alert = NSAlert()
                if let error {
                    alert.messageText = "Couldn't set Muninn as the default browser"
                    alert.informativeText = "\(error.localizedDescription)\n\nYou can set it in System Settings › Desktop & Dock › Default web browser."
                } else {
                    alert.messageText = "Muninn is now your default browser"
                    alert.informativeText = "Links from other apps will open in a Quick Look window."
                }
                alert.runModal()
            }
        }
    }

    @objc private func clearProfileData() {
        let profileName = profiles.first { $0.id == currentProfileId }?.name ?? "current"
        let alert = NSAlert()
        alert.messageText = "Clear the \(profileName) profile’s data?"
        alert.informativeText = "Removes history, cookies, logins, and cached site data for this profile only. Other profiles are unaffected."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        currentHistory.clear()
        dataStore(forProfile: currentProfileId).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                           modifiedSince: .distantPast) { }
        loadLanding(activeTab) // refresh the new-tab suggestions
    }

    // MARK: - profiles (separate cookie/login jars)

    /// The (isolated, persistent) data store for a profile. The default profile keeps the shared
    /// `.default()` store so existing logins survive; other profiles get their own jar.
    private func dataStore(forProfile id: UUID) -> WKWebsiteDataStore {
        if id == defaultProfileId { return .default() }
        if let s = dataStores[id] { return s }
        let s = WKWebsiteDataStore(forIdentifier: id)
        dataStores[id] = s
        return s
    }
    private func dataStore(forWorkspace wid: UUID) -> WKWebsiteDataStore {
        dataStore(forProfile: workspaces.first { $0.id == wid }?.profileId ?? defaultProfileId)
    }

    /// The active workspace's profile.
    private var currentProfileId: UUID {
        workspaces.first { $0.id == activeWorkspaceId }?.profileId ?? defaultProfileId
    }
    private var currentProfile: Profile? { profiles.first { $0.id == currentProfileId } }
    private var currentSearchEngine: SearchEngine { currentProfile?.searchEngine ?? .duckduckgo }
    private var currentAutoArchive: AutoArchive { currentProfile?.autoArchive ?? .d1 }
    private var suggestionsEnabled: Bool { currentProfile?.suggestionsEnabled ?? true }
    /// Per-profile history store (the default profile keeps `history.json`).
    private func history(forProfile id: UUID) -> HistoryStore {
        if let h = historyStores[id] { return h }
        let name = id == defaultProfileId ? "history.json" : "history-\(id.uuidString).json"
        let h = HistoryStore(fileName: name)
        historyStores[id] = h
        return h
    }
    /// History for the active profile — feeds recording, autocomplete, and the command bar.
    private var currentHistory: HistoryStore { history(forProfile: currentProfileId) }

    /// Assign a workspace to a profile and re-create its tabs in that profile's data store.
    @objc private func setWorkspaceProfile(_ s: NSMenuItem) {
        guard let comps = (s.representedObject as? String)?.split(separator: "|"), comps.count == 2,
              let wid = UUID(uuidString: String(comps[0])), let pid = UUID(uuidString: String(comps[1])),
              let wi = workspaceIndex(wid) else { return }
        workspaces[wi].profileId = pid
        reprofileWorkspace(wid)
        rebuildTabBar(); persist()
    }

    @objc private func newProfileForWorkspace(_ s: NSMenuItem) {
        guard let wid = (s.representedObject as? String).flatMap(UUID.init), let wi = workspaceIndex(wid) else { return }
        guard let name = promptForText(title: "New Profile", message: "Name this profile:", initial: "Work") else { return }
        let p = Profile(name: name, colorIndex: profiles.count % Folder.palette.count)
        profiles.append(p)
        workspaces[wi].profileId = p.id
        reprofileWorkspace(wid)
        rebuildTabBar(); persist()
    }

    /// Re-create every tab in a workspace so they use its (new) profile's data store. Regular
    /// tabs reload; pinned/favourite tabs stay lazy and reload on next select.
    private func reprofileWorkspace(_ wid: UUID) {
        let store = dataStore(forWorkspace: wid)
        let active = tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
        for i in tabs.indices where tabs[i].workspaceId == wid {
            let old = tabs[i]
            let fresh = BrowserTab(id: old.id, broker: broker, dataStore: store)
            fresh.kind = old.kind; fresh.folderId = old.folderId; fresh.workspaceId = wid
            fresh.splitGroupId = old.splitGroupId; fresh.homeURL = old.homeURL
            fresh.setInitialTitle(old.title); fresh.customTitle = old.customTitle
            fresh.pendingURL = old.currentURL // reload lazily (or on show)
            configureTab(fresh)
            if old.id == miniTabId { stopMiniPlayer() }
            old.stop()
            tabs[i] = fresh
        }
        if let a = active, let ai = tabs.firstIndex(where: { $0.id == a.id }) { activeIndex = ai }
        activeTab.ensureLoaded()
        showActiveWebView()
    }

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

    /// The active workspace's background tint (blend of the base bg + workspace colour).
    private func currentTintColor() -> NSColor {
        let base = NSColor.underPageBackgroundColor
        guard let ws = workspaces.first(where: { $0.id == activeWorkspaceId }) else { return base }
        return base.blended(withFraction: 0.20, of: wsColor(ws)) ?? base
    }

    /// Tint the sidebar + window background with the active workspace's colour — the visual
    /// "where am I" cue, extending under the traffic-light bar and around the floating card.
    private func applyWorkspaceTint() {
        let tint = currentTintColor()
        sidebar.layer?.backgroundColor = tint.cgColor
        window.contentView?.layer?.backgroundColor = tint.cgColor
        toolsSidebar.applyTint(tint)
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
        let outgoing = activeTab
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
        popOutIfPlaying(outgoing) // switching workspace away from a playing tab → Mini Player
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

        // Profile — the workspace's cookie/login jar.
        let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let currentProfile = workspaceIndex(id).flatMap { workspaces[$0].profileId } ?? defaultProfileId
        for p in profiles {
            let m = NSMenuItem(title: p.name, action: #selector(setWorkspaceProfile(_:)), keyEquivalent: "")
            m.target = self
            m.representedObject = "\(id.uuidString)|\(p.id.uuidString)"
            if p.id == currentProfile { m.state = .on }
            sub.addItem(m)
        }
        sub.addItem(.separator())
        sub.addItem(item("New Profile…", #selector(newProfileForWorkspace(_:))))
        profileItem.submenu = sub
        menu.addItem(profileItem)

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
        if tabs[index].id == miniTabId { stopMiniPlayer() } // reclaim the borrowed web view first
        // A split member "closes" out of the split rather than closing the tab.
        if tabs[index].splitGroupId != nil {
            removeFromSplit(index)
            return
        }
        // Favourites/pinned aren't removed by close — they unload (free memory) but stay
        // in the sidebar, reloading lazily when picked again.
        if tabs[index].kind != .regular {
            unloadTab(index)
            return
        }
        let active = activeTab
        let closingActive = tabs[index] === active
        if let saved = tabs[index].saved() { closedTabs.append(saved) } // for Cmd+Shift+T
        extensionBridge.didClose(tabs[index])
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

    /// Unload a favourite/pinned tab (frees its page) and move off it if it was active.
    private func unloadTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        let wasActive = tabs[index] === activeTab
        tabs[index].unload()
        if wasActive {
            if let i = tabs.firstIndex(where: { $0.workspaceId == activeWorkspaceId && $0 !== tabs[index] }) {
                selectTab(i)
            } else {
                let t = makeTab(); t.workspaceId = activeWorkspaceId; tabs.append(t)
                activeIndex = tabs.count - 1
                showActiveWebView(); loadLanding(t)
            }
        }
        rebuildTabBar()
    }

    // MARK: - keyboard actions

    /// Cmd+D — pin/unpin the active tab.
    @objc private func togglePinActive() {
        setKind(activeIndex, activeTab.kind == .pinned ? .regular : .pinned)
    }

    /// Cmd+Shift+T — reopen the most recently closed regular tab.
    @objc private func reopenLastClosed() {
        guard let saved = closedTabs.popLast(), let url = URL(string: saved.url) else { return }
        let tab = makeTab(); tab.workspaceId = activeWorkspaceId
        tabs.append(tab); extensionBridge.didOpen(tab); activeIndex = tabs.count - 1
        showActiveWebView(); tab.load(url); rebuildTabBar()
    }

    /// Cmd+Shift+C — copy the active tab's URL.
    @objc private func copyActiveURL() {
        guard let url = activeWebView.url ?? activeTab.currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast("Link copied", share: [url])
    }

    /// Cmd+Shift+Option+C — copy the active tab's URL as a Markdown link.
    @objc private func copyActiveMarkdown() {
        guard let url = activeWebView.url ?? activeTab.currentURL else { return }
        let title = activeTab.title.isEmpty ? url.absoluteString : activeTab.title
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(title)](\(url.absoluteString))", forType: .string)
        showToast("Copied as Markdown", share: [url])
    }

    /// A small transient toast in the top-right, tinted to the current workspace, with an
    /// optional Share button (standard macOS share sheet: AirDrop, Mail, Messages, …).
    private func showToast(_ message: String, share items: [Any] = [], record: Bool = true) {
        if record { notificationStore.add(message) } // keep in the Notifications history
        guard let content = window.contentView else { return }
        currentToast?.removeFromSuperview()
        toastDismiss?.cancel()
        toastShareItems = items
        toastPinned = false

        let tint = currentTintColor()
        let fg = Self.contrastingText(tint)
        let container = HoverView()
        container.wantsLayer = true
        container.layer?.backgroundColor = tint.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = fg.withAlphaComponent(0.12).cgColor
        container.shadow = NSShadow()
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.22
        container.layer?.shadowRadius = 12
        container.layer?.shadowOffset = CGSize(width: 0, height: -3)
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = fg
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 38),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        var dismissDelay = 1.8
        if !items.isEmpty {
            // Share button as a filled accent chip so it clearly pops — inset from the
            // container's rounded corner so it can't spill past it.
            let share = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")!
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))!,
                                 target: self, action: #selector(shareToast(_:)))
            share.isBordered = false
            share.contentTintColor = .white
            share.wantsLayer = true
            share.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            share.layer?.cornerRadius = 5
            share.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(share)
            NSLayoutConstraint.activate([
                share.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
                share.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                share.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                share.widthAnchor.constraint(equalToConstant: 24),
                share.heightAnchor.constraint(equalToConstant: 20),
            ])
            dismissDelay = 4.0 // give time to hit Share
        } else {
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14).isActive = true
        }

        // Hover keeps it up; leaving lets it fade shortly after.
        container.onEntered = { [weak self] in self?.toastDismiss?.cancel() }
        container.onExited = { [weak self, weak container] in
            guard let self, !self.toastPinned else { return }
            let work = DispatchWorkItem { [weak self, weak container] in self?.dismissToast(container) }
            self.toastDismiss = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        content.addSubview(container)
        NSLayoutConstraint.activate([
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: content.topAnchor, constant: 46),
        ])
        currentToast = container

        // Smooth slide-in from the right + fade.
        container.alphaValue = 0
        container.layer?.setAffineTransform(CGAffineTransform(translationX: 24, y: 0))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            container.animator().alphaValue = 1
            container.layer?.setAffineTransform(.identity)
        }

        let work = DispatchWorkItem { [weak self, weak container] in self?.dismissToast(container) }
        toastDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay, execute: work)
    }

    private func dismissToast(_ toast: NSView?) {
        guard let toast, !toastPinned else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            toast.animator().alphaValue = 0
            toast.layer?.setAffineTransform(CGAffineTransform(translationX: 24, y: 0))
        }, completionHandler: { [weak self, weak toast] in
            toast?.removeFromSuperview()
            if self?.currentToast === toast { self?.currentToast = nil }
        })
    }

    @objc private func shareToast(_ sender: NSButton) {
        guard !toastShareItems.isEmpty else { return }
        // Haptic tap (Force Touch trackpads) + a quick press flash for visual feedback.
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        let pressed = NSColor.controlAccentColor.blended(withFraction: 0.35, of: .black)?.cgColor
        sender.layer?.backgroundColor = pressed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak sender] in
            sender?.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
        toastDismiss?.cancel()
        toastPinned = true // keep the toast anchored while the share sheet is open
        let picker = NSSharingServicePicker(items: toastShareItems)
        picker.delegate = self
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    /// Cmd+Shift+K — close all unpinned (regular) tabs in the active workspace.
    @objc private func clearUnpinnedTabs() {
        let victims = tabs.enumerated().filter { $0.element.kind == .regular && $0.element.workspaceId == activeWorkspaceId }
        for (_, tab) in victims { if let s = tab.saved() { closedTabs.append(s) }; tab.stop() }
        let victimSet = Set(victims.map { ObjectIdentifier($0.element) })
        tabs.removeAll { victimSet.contains(ObjectIdentifier($0)) }
        if !tabs.contains(where: { $0.workspaceId == activeWorkspaceId }) {
            let t = makeTab(); t.workspaceId = activeWorkspaceId; tabs.append(t)
            activeIndex = tabs.count - 1; loadLanding(t)
        } else {
            activeIndex = tabs.firstIndex { $0.workspaceId == activeWorkspaceId } ?? 0
        }
        showActiveWebView(); rebuildTabBar(); persist()
    }

    /// Open a URL in a new regular tab in the active workspace.
    private func openInNewTab(_ url: URL) {
        let tab = makeTab(); tab.workspaceId = activeWorkspaceId
        tabs.append(tab); extensionBridge.didOpen(tab); activeIndex = tabs.count - 1
        showActiveWebView(); tab.load(url); rebuildTabBar()
    }

    // MARK: - Developer Mode

    /// Open the page's HTML source in a new tab (Developer Mode / ⌥⌘U).
    func viewSource(of webView: WKWebView) {
        let sourceURL = webView.url
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            let html = (result as? String) ?? ""
            let escaped = html
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let title = sourceURL?.host.map { "Source of \($0)" } ?? "Page Source"
            let page = """
            <!doctype html><meta charset="utf-8"><title>\(title)</title>
            <style>body{margin:0;background:#1e1e1e;color:#d4d4d4}
            pre{padding:16px;white-space:pre-wrap;word-break:break-word;
            font:12px ui-monospace,SFMono-Regular,Menlo,monospace;line-height:1.5}</style>
            <pre>\(escaped)</pre>
            """
            self?.openHTMLInNewTab(page)
        }
    }

    private func openHTMLInNewTab(_ html: String) {
        let tab = makeTab(); tab.workspaceId = activeWorkspaceId
        tabs.append(tab); activeIndex = tabs.count - 1
        showActiveWebView(); tab.webView.loadHTMLString(html, baseURL: nil); rebuildTabBar()
    }

    /// Inspect the active tab's web view (Developer Mode / ⌥⌘I).
    private func inspectActiveTab() { (activeWebView as? MuninnWebView)?.showInspector() }

    // Developer Mode settings (Settings → Advanced).
    var settingsDeveloperMode: Bool {
        get { AppSettings.developerMode }
        set {
            AppSettings.developerMode = newValue
            if #available(macOS 13.3, *) { for t in tabs { t.webView.isInspectable = newValue } }
        }
    }

    // MARK: - link routing (Air Traffic Control)

    /// Open a URL honoring routing rules. If a rule targets a *different* space, switch there
    /// and open a new tab; otherwise load it here (`newTab` picks new-tab vs current-tab).
    /// Returns true if it re-homed the URL to another space.
    @discardableResult
    private func openRouted(_ url: URL, newTab: Bool) -> Bool {
        if let rule = routingRules.first(where: { $0.matches(url) }),
           rule.workspaceId != activeWorkspaceId,
           workspaces.contains(where: { $0.id == rule.workspaceId }) {
            switchWorkspace(to: rule.workspaceId)
            openInNewTab(url)
            return true
        }
        if newTab { openInNewTab(url) } else { activeTab.load(url) }
        return false
    }

    /// Route an incoming link: if a rule matches its host, open it in that rule's workspace
    /// (switching to it — which also switches profile). Otherwise open a Quick Look.
    func route(_ url: URL) {
        guard url.scheme?.hasPrefix("http") == true else { return }
        if let rule = routingRules.first(where: { $0.matches(url) }),
           workspaces.contains(where: { $0.id == rule.workspaceId }) {
            switchWorkspace(to: rule.workspaceId) // no-op if already active
            openInNewTab(url)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openQuickLook(url)
        }
    }

    // Routing settings API (used by SettingsWindowController).
    func settingsRoutingRules() -> [RoutingRule] { routingRules }
    func settingsWorkspacePicker() -> [(id: UUID, name: String)] { workspaces.map { ($0.id, $0.name) } }
    func settingsAddRule() {
        guard let wid = workspaces.first?.id else { return }
        routingRules.append(RoutingRule(workspaceId: wid)); persist()
    }
    func settingsRemoveRule(_ id: UUID) { routingRules.removeAll { $0.id == id }; persist() }
    func settingsUpdateRule(_ id: UUID, host: String? = nil, workspaceId: UUID? = nil) {
        guard let i = routingRules.firstIndex(where: { $0.id == id }) else { return }
        if let host { routingRules[i].host = host.trimmingCharacters(in: .whitespaces) }
        if let workspaceId { routingRules[i].workspaceId = workspaceId }
        persist()
    }

    // MARK: - Obsidian

    /// The active page's title, URL, and visible text (used by Ask context + Obsidian notes).
    private func currentPageText(_ completion: @escaping (_ title: String, _ url: String, _ text: String) -> Void) {
        let title = activeTab.title
        let url = activeWebView.url?.absoluteString ?? ""
        activeWebView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
            completion(title, url, String((result as? String ?? "").prefix(12000)))
        }
    }

    /// Create an Obsidian note from the current page (frontmatter + URL), then open it in Obsidian.
    private func newNoteFromPage() {
        guard ObsidianSettings.isConfigured, let folder = ObsidianSettings.notesFolder else {
            showToast("Set your Obsidian vault in Settings → Obsidian"); return
        }
        let title = activeTab.title.isEmpty ? (activeWebView.url?.host ?? "Note") : activeTab.title
        let url = activeWebView.url?.absoluteString ?? ""
        do {
            let file = try ObsidianNote.create(title: title, url: url, summary: nil, in: folder)
            if let open = ObsidianNote.openURL(for: file) { NSWorkspace.shared.open(open) }
            showToast("Note created in Obsidian")
        } catch { showToast("Couldn't create the note") }
    }

    /// Summarize the current page with the local model and save it as an Obsidian note — fully
    /// automatic (no chat UI); a toast confirms when the note is written.
    private func summarizePageToNote() {
        guard ObsidianSettings.isConfigured, let folder = ObsidianSettings.notesFolder else {
            showToast("Set your Obsidian vault in Settings → Obsidian"); return
        }
        let model = OllamaSettings.defaultModel
        guard !model.isEmpty, let base = OllamaSettings.baseURLValue else {
            showToast("Configure a local model in Settings → Models"); return
        }
        showToast("Summarizing page…", record: false) // progress, not a kept notification
        currentPageText { [weak self] title, url, text in
            guard let self else { return }
            let prompt = """
            Summarize the web page below into a concise Markdown note: start with a one-line **TL;DR**, \
            then 3–6 key bullet points. Output only the summary — do not repeat the raw text.

            Title: \(title)
            URL: \(url)

            \(text)
            """
            let client = OllamaClient(baseURL: base)
            self.askTask?.cancel()
            self.askTask = Task { @MainActor in
                var summary = ""
                do {
                    for try await token in client.generateStream(model: model, prompt: prompt) { summary += token }
                } catch {
                    self.showToast("Summary failed — is Ollama running?"); return
                }
                do {
                    let file = try ObsidianNote.create(title: title, url: url, summary: summary, in: folder)
                    if let open = ObsidianNote.openURL(for: file) { NSWorkspace.shared.open(open) }
                    self.showToast("Summary note created in Obsidian")
                } catch { self.showToast("Couldn't create the note") }
            }
        }
    }

    // MARK: - Quick Look (Little Muninn)

    /// Open a compact, ephemeral Quick Look window (Cmd+Option+N, or an external link when
    /// Muninn is the default browser). `url` nil → open focused on the address field.
    func openQuickLook(_ url: URL?) {
        let ql = QuickLookWindow(broker: broker, id: nextQuickLookId); nextQuickLookId += 1
        ql.onPromote = { [weak self] u in self?.promoteToTab(u) }
        ql.onClosed = { [weak self] q in self?.quickLooks.removeAll { $0 === q } }
        quickLooks.append(ql)
        ql.present()
        if let url { ql.load(url) } else { ql.focusAddress() }
    }

    /// "Open in Muninn" from a Quick Look — promote the page to a tab and surface the window.
    private func promoteToTab(_ url: URL) {
        openInNewTab(url)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - command palette (Cmd+N)

    @objc private func openCommandPalette() {
        if palette != nil { return }
        guard let content = window.contentView else { return }
        let p = CommandPalette()
        p.openTabs = tabs.filter { $0.workspaceId == activeWorkspaceId }.map { ($0.id, $0.title, $0.currentURL) }
        p.history = suggestionsEnabled ? currentHistory.entries : []
        p.commands = paletteCommands()
        p.searchEngineName = currentSearchEngine.displayName
        p.onClose = { [weak self] in self?.closeCommandPalette() }
        p.onExecute = { [weak self] item in
            guard let self else { return }
            switch item.kind {
            case .tab(let id): if let i = self.tabIndex(id: id) { self.selectTab(i) }
            case .url(let url): self.openRouted(url, newTab: true)
            case .search(let q): self.openInNewTab(currentSearchEngine.url(q))
            case .command(let id): self.closeCommandPalette(); self.runPaletteCommand(id); return
            }
            self.closeCommandPalette()
        }
        palette = p
        p.activate(in: content)
    }

    private func closeCommandPalette() {
        palette?.removeFromSuperview()
        palette = nil
        window.makeFirstResponder(activeWebView)
    }

    /// The app-action commands offered in the palette. "Switch Space" expands to one entry per
    /// workspace (so typing a space name autocompletes to it). Developer-mode entries appear only
    /// when Developer Mode is on. Shortcut hints come from the (remappable) `ShortcutStore`.
    private func paletteCommands() -> [CommandPalette.Command] {
        func sc(_ a: ShortcutAction) -> String { ShortcutStore.shortcut(for: a).display }
        var cmds: [CommandPalette.Command] = [
            .init(id: "pin", title: "Pin Current Tab", symbol: "pin", shortcut: nil),
            .init(id: "unpin", title: "Unpin Current Tab", symbol: "pin.slash", shortcut: nil),
            .init(id: "favourite", title: "Favourite Current Tab", symbol: "star", shortcut: nil),
            .init(id: "unfavourite", title: "Unfavourite Current Tab", symbol: "star.slash", shortcut: nil),
            .init(id: "cleanUp", title: "Clean Up", symbol: "sparkles", shortcut: sc(.clearUnpinned)),
            .init(id: "toggleSidebar", title: "Toggle Sidebar", symbol: "sidebar.left", shortcut: nil),
            .init(id: "toolsSidebar", title: "Toggle Tools Sidebar", symbol: "sidebar.right", shortcut: sc(.toolsSidebar)),
            .init(id: "openLast", title: "Open Last Tab", symbol: "arrow.uturn.left", shortcut: sc(.reopenClosed)),
            .init(id: "reload", title: "Reload", symbol: "arrow.clockwise", shortcut: sc(.reload)),
            .init(id: "copyURL", title: "Copy URL", symbol: "link", shortcut: sc(.copyURL)),
            .init(id: "settings", title: "Open Settings", symbol: "gearshape", shortcut: sc(.settings)),
            .init(id: "taskManager", title: "Task Manager", symbol: "gauge.with.dots.needle.bottom.50percent", shortcut: nil),
            .init(id: "translatePage", title: "Translate Page", symbol: "translate", shortcut: nil),
            .init(id: "reminders", title: "Show Reminders", symbol: "checklist", shortcut: nil),
            .init(id: "newReminder", title: "New Reminder…", symbol: "plus.circle", shortcut: nil),
            .init(id: "reminderFromPage", title: "New Reminder from Page", symbol: "bookmark", shortcut: nil),
            .init(id: "listFromPage", title: "Create Reminders List from Page", symbol: "list.bullet.rectangle", shortcut: nil),
            .init(id: "askModel", title: "Ask Local Model…", symbol: "sparkles", shortcut: nil),
        ]
        if ObsidianSettings.isConfigured {
            cmds.append(.init(id: "newNote", title: "New Note from Page (Obsidian)", symbol: "square.and.pencil", shortcut: nil))
            if !OllamaSettings.defaultModel.isEmpty {
                cmds.append(.init(id: "summarizeNote", title: "Summarize Page → Obsidian Note", symbol: "text.append", shortcut: nil))
            }
        }
        // Switch Space — one entry per workspace (all but the active one).
        for ws in workspaces where ws.id != activeWorkspaceId {
            let label = [ws.icon, ws.name].compactMap { $0 }.joined(separator: " ")
            cmds.append(.init(id: "space:\(ws.id.uuidString)", title: "Switch Space: \(label)", symbol: "square.stack", shortcut: nil))
        }
        if AppSettings.developerMode {
            cmds.append(.init(id: "inspect", title: "Open Inspector", symbol: "ladybug", shortcut: "⌥⌘I"))
            cmds.append(.init(id: "viewSource", title: "View Page Source", symbol: "chevron.left.forwardslash.chevron.right", shortcut: "⌥⌘U"))
        }
        return cmds
    }

    // MARK: - Task Manager

    @objc func openTaskManager() {
        let tm = taskManager ?? {
            let w = TaskManagerWindow()
            w.provider = { [weak self] in self?.taskManagerRows() ?? [] }
            w.onSelect = { [weak self] id in self?.taskManagerSelect(id) }
            w.onReload = { [weak self] id in self?.tabById(id)?.webView.reload() }
            w.onClose = { [weak self] id in if let i = self?.tabIndex(id: id) { self?.closeTab(i) } }
            self.taskManager = w
            return w
        }()
        tm.present()
    }

    private func tabById(_ id: Int) -> BrowserTab? { tabs.first { $0.id == id } }

    private func taskManagerSelect(_ id: Int) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs[i].workspaceId != activeWorkspaceId, let wid = tabs[i].workspaceId { switchWorkspace(to: wid) }
        if let j = tabs.firstIndex(where: { $0.id == id }) { selectTab(j) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    /// Snapshot each loaded tab's WebContent process memory + responsiveness (sorted by memory).
    private func taskManagerRows() -> [TaskManagerRow] {
        pingTabsForTaskManager()
        struct Live { let id: Int; let title: String; let fav: NSImage?; let pid: pid_t; let active: Bool; let ok: Bool }
        let live: [Live] = tabs.compactMap { tab in
            // Any tab with a running WebContent process (landing page, loaded URL, …) — not our
            // lazy `isLoaded` flag, which is only set on URL navigation.
            guard let pid = (tab.webView.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value, pid > 0
            else { return nil }
            return Live(id: tab.id, title: tab.displayTitle, fav: tab.favicon, pid: pid,
                        active: tab === activeTab, ok: tabResponsive[tab.id] ?? true)
        }
        let mem = ProcessMemory.residentMB(pids: live.map { $0.pid })
        return live.map { l in
            TaskManagerRow(tabId: l.id, title: l.title, favicon: l.fav, pid: l.pid,
                           memoryMB: mem[l.pid] ?? 0, responsive: l.ok, isActive: l.active)
        }.sorted { $0.memoryMB > $1.memoryMB }
    }

    /// Ping each loaded tab (trivial JS). If a ping stays outstanding > 4s, the tab is unresponsive.
    private func pingTabsForTaskManager() {
        let liveIds = Set(tabs.map { $0.id })
        tabResponsive = tabResponsive.filter { liveIds.contains($0.key) }
        tabPingPending = tabPingPending.filter { liveIds.contains($0.key) }
        for tab in tabs {
            if let sent = tabPingPending[tab.id] {
                if Date().timeIntervalSince(sent) > 4 { tabResponsive[tab.id] = false }
                continue // still awaiting the previous ping
            }
            tabPingPending[tab.id] = Date()
            let id = tab.id
            tab.webView.evaluateJavaScript("true") { [weak self] _, _ in
                MainActor.assumeIsolated { self?.tabResponsive[id] = true; self?.tabPingPending[id] = nil }
            }
        }
    }

    /// Run a palette command by id from outside (e.g. menu items).
    func performCommand(_ id: String) { runPaletteCommand(id) }

    private func runPaletteCommand(_ id: String) {
        if id.hasPrefix("space:"), let uuid = UUID(uuidString: String(id.dropFirst("space:".count))) {
            switchWorkspace(to: uuid); return
        }
        switch id {
        case "pin":           setKind(activeIndex, .pinned)
        case "unpin":         setKind(activeIndex, .regular)
        case "favourite":     setKind(activeIndex, .favourite)
        case "unfavourite":   setKind(activeIndex, .regular)
        case "cleanUp":       clearUnpinnedTabs()
        case "toggleSidebar": toggleSidebar()
        case "toolsSidebar":  toggleToolsSidebar()
        case "openLast":      reopenLastClosed()
        case "reload":        reload()
        case "copyURL":       copyActiveURL()
        case "settings":      openSettings()
        case "taskManager":   openTaskManager()
        case "translatePage": translateButtonClicked()
        case "reminders":         revealRemindersTool()
        case "newReminder":       newReminder()
        case "reminderFromPage":  reminderFromPage()
        case "listFromPage":      listFromPage()
        case "inspect":       inspectActiveTab()
        case "viewSource":    viewSource(of: activeWebView)
        case "askModel":      openAskModel()
        case "newNote":       newNoteFromPage()
        case "summarizeNote": summarizePageToNote()
        default:              break
        }
    }

    // MARK: - Library

    /// Animate a file icon "dropping" from the top into the Library button, then pulse the button.
    private func flyToLibrary(icon: NSImage) {
        guard let content = window.contentView else { return }
        let iv = NSImageView(image: icon)
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true; iv.layer?.cornerRadius = 5; iv.layer?.masksToBounds = true
        iv.shadow = NSShadow(); iv.layer?.shadowOpacity = 0.3; iv.layer?.shadowRadius = 6
        let size: CGFloat = 44
        let target = content.convert(libraryButton.bounds, from: libraryButton)
        // Straight vertical drop: start directly above the Library button.
        iv.frame = NSRect(x: target.midX - size / 2, y: content.bounds.maxY - 150, width: size, height: size)
        content.addSubview(iv)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            iv.animator().frame = NSRect(x: target.midX - 6, y: target.midY - 6, width: 12, height: 12)
            iv.animator().alphaValue = 0.1
        }, completionHandler: { [weak self] in
            iv.removeFromSuperview()
            self?.pulseLibraryButton()
        })
    }

    /// A quick accent flash on the Library button (paired with the drop animation).
    private func pulseLibraryButton() {
        libraryButton.wantsLayer = true
        libraryButton.layer?.cornerRadius = 6
        let flash = CABasicAnimation(keyPath: "backgroundColor")
        flash.fromValue = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        flash.toValue = NSColor.clear.cgColor
        flash.duration = 0.45
        flash.timingFunction = CAMediaTimingFunction(name: .easeOut)
        libraryButton.layer?.add(flash, forKey: "pulse")
    }

    @objc private func openLibrary() {
        if let pane = libraryPane { pane.close(); return } // toggle closed
        guard let content = window.contentView else { return }
        let pane = LibraryPane(store: downloadStore, tint: currentTintColor())
        pane.onClose = { [weak self] in self?.libraryPane = nil }
        libraryPane = pane
        pane.present(in: content)
    }

    // MARK: - Ask Local Model (Ollama)

    /// Reveal the Ask chat tool in the Tools sidebar (non-blocking; keep browsing).
    private func openAskModel() {
        if !toolsOpen { setToolsOpen(true, animated: true) }
        toolsSidebar.selectTool("ask")
        askChat.focusInput()
    }

    /// Stream a chat turn from the configured local model into the chat view.
    private func runChatTurn(_ messages: [ChatMessage],
                             onToken: @escaping (String) -> Void, onDone: @escaping (Error?) -> Void) {
        let model = OllamaSettings.defaultModel
        guard !model.isEmpty else {
            onDone(OllamaError.unreachable("No default model. Set one in Settings → Models.")); return
        }
        guard let base = OllamaSettings.baseURLValue else { onDone(OllamaError.badURL); return }
        let payload = messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        let client = OllamaClient(baseURL: base)
        askTask?.cancel()
        askTask = Task { @MainActor in
            do {
                for try await token in client.chatStream(model: model, messages: payload) { onToken(token) }
                onDone(nil)
            } catch is CancellationError {
                onDone(nil)
            } catch {
                onDone(error)
            }
        }
    }

    /// Render whatever the active tab entails — its split group, or itself alone.
    private func showActiveWebView() { showVisibleTabs(); refreshExtensionActive() }

    // MARK: - Browser extensions toolbar

    /// Notify extensions the active tab changed, and refresh the action toolbar's per-tab state.
    private func refreshExtensionActive() {
        guard !tabs.isEmpty else { return }
        let cur = activeTab
        if cur.id != lastNotifiedActiveTabId {
            let prev = tabs.first { $0.id == lastNotifiedActiveTabId }
            extensionBridge.didActivate(cur, previous: prev)
            lastNotifiedActiveTabId = cur.id
        }
        rebuildExtensionToolbar()
    }

    /// One button per loaded extension's action (for the active tab); click → popup or click event.
    private func rebuildExtensionToolbar() {
        extensionBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        extActionButtons.removeAll()
        guard !tabs.isEmpty else { return }
        let proxy = extensionBridge.proxy(for: activeTab)
        for context in ExtensionManager.shared.loadedContexts {
            guard let action = context.action(for: proxy) else { continue }
            let b = HoverIconButton()
            b.isBordered = false
            b.restingTint = .labelColor
            b.translatesAutoresizingMaskIntoConstraints = false
            b.imagePosition = .imageOnly
            b.image = action.icon(for: CGSize(width: 16, height: 16))
                ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
            let name = context.webExtension.displayName ?? "Extension"
            b.toolTip = action.label.isEmpty ? name : action.label
            b.target = self; b.action = #selector(extensionActionClicked(_:))
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            extActionButtons[b] = context
            extensionBar.addArrangedSubview(b)
        }
    }

    @objc private func extensionActionClicked(_ sender: NSButton) {
        guard let context = extActionButtons[sender], !tabs.isEmpty else { return }
        let proxy = extensionBridge.proxy(for: activeTab)
        guard let action = context.action(for: proxy) else { return }
        // Canonical path: performAction prepares + sizes the popup and drives the presentActionPopup
        // delegate (WebKit controls the popup web view's viewport; hosting it ourselves fails).
        context.performAction(for: proxy)
    }

    private func pin(_ v: NSView, to parent: NSView) {
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: parent.topAnchor),
            v.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    /// Ids of the active tab's split group (2–4), or just the active tab.
    private func groupMemberIds(_ gid: UUID) -> [Int] { tabs.filter { $0.splitGroupId == gid }.map { $0.id } }

    /// Render the visible tab(s): a single rounded web view, or an NSSplitView of 2–4 panes.
    private func showVisibleTabs() {
        hidePeek() // navigating the main content dismisses any open Peek
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        if let gid = activeTab.splitGroupId { visibleTabIds = groupMemberIds(gid) }
        else { visibleTabIds = [activeTab.id] }

        if visibleTabIds.count == 1 {
            let web = activeWebView
            web.translatesAutoresizingMaskIntoConstraints = false
            web.wantsLayer = true
            web.layer?.cornerRadius = 10 // clip page content to the floating card's corners
            web.layer?.masksToBounds = true
            webContainer.addSubview(web)
            pin(web, to: webContainer)
        } else {
            let split = NSSplitView()
            split.isVertical = true // vertical dividers → panes side by side
            split.dividerStyle = .thin
            split.translatesAutoresizingMaskIntoConstraints = false
            for id in visibleTabIds {
                guard let i = tabIndex(id: id) else { continue }
                tabs[i].ensureLoaded()
                split.addSubview(makePane(index: i, active: i == activeIndex))
            }
            webContainer.addSubview(split)
            pin(split, to: webContainer)
            // Distribute the panes evenly once laid out.
            DispatchQueue.main.async { [weak split] in
                guard let split, split.bounds.width > 0 else { return }
                let n = split.subviews.count
                for d in 0..<max(n - 1, 0) {
                    split.setPosition(split.bounds.width * CGFloat(d + 1) / CGFloat(n), ofDividerAt: d)
                }
            }
        }
        updateChrome()
    }

    /// One split-view pane: the tab's web view in a rounded card, accent border when active,
    /// with a hover × to drop it from the split.
    private func makePane(index: Int, active: Bool) -> NSView {
        let pane = NSView()
        pane.wantsLayer = true
        pane.layer?.cornerRadius = 10
        pane.layer?.masksToBounds = true
        pane.layer?.borderWidth = active ? 2 : 0
        pane.layer?.borderColor = NSColor.controlAccentColor.cgColor

        let web = tabs[index].webView
        web.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(web)
        pin(web, to: pane)

        let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close pane")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        let close = HoverCloseButton(image: xmark ?? NSImage(), target: self, action: #selector(closePaneButton(_:)))
        close.tag = tabs[index].id // stable id (index can shift)
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.wantsLayer = true
        close.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        close.layer?.cornerRadius = 9
        close.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: pane.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -8),
            close.widthAnchor.constraint(equalToConstant: 18),
            close.heightAnchor.constraint(equalToConstant: 18),
        ])
        return pane
    }

    @objc private func closePaneButton(_ sender: NSButton) {
        if let i = tabIndex(id: sender.tag) { removeFromSplit(i) }
    }

    // MARK: - split view

    private func groupCount(_ gid: UUID) -> Int { tabs.filter { $0.splitGroupId == gid }.count }

    /// Split the active tab with `index` (or add `index` to the active tab's existing group).
    /// Regular tabs only.
    private func addToSplit(_ index: Int) {
        guard tabs.indices.contains(index), tabs[index].kind == .regular, activeTab.kind == .regular else { return }
        if let gid = activeTab.splitGroupId {
            guard tabs[index].splitGroupId != gid, groupCount(gid) < 4 else { return }
            tabs[index].splitGroupId = gid
        } else {
            guard index != activeIndex else { return }
            let gid = UUID()
            activeTab.splitGroupId = gid
            tabs[index].splitGroupId = gid
        }
        activeIndex = index
        tabs[index].ensureLoaded()
        showVisibleTabs(); rebuildTabBar()
    }

    /// Drag one tab onto another → split the two (or add the dragged tab to the target's group).
    private func dropSplit(_ draggedId: Int, onto targetId: Int) {
        guard draggedId != targetId, let d = tabIndex(id: draggedId), let t = tabIndex(id: targetId),
              tabs[d].kind == .regular, tabs[t].kind == .regular else { return }
        let gid = tabs[t].splitGroupId ?? UUID()
        guard tabs[d].splitGroupId != gid, groupCount(gid) < 4 else { return }
        tabs[t].splitGroupId = gid
        tabs[d].splitGroupId = gid
        activeIndex = d
        tabs[d].ensureLoaded(); tabs[t].ensureLoaded()
        showVisibleTabs(); rebuildTabBar()
    }

    /// Drop a tab from its split (the tab stays open). If ≤1 member remains, the group dissolves.
    private func removeFromSplit(_ index: Int) {
        guard tabs.indices.contains(index), let gid = tabs[index].splitGroupId else { return }
        let wasActive = index == activeIndex
        tabs[index].splitGroupId = nil
        let remaining = tabs.enumerated().filter { $0.element.splitGroupId == gid }
        if remaining.count <= 1 { remaining.forEach { tabs[$0.offset].splitGroupId = nil } }
        if wasActive, let firstOther = remaining.first?.offset { activeIndex = firstOther }
        showVisibleTabs(); rebuildTabBar()
    }

    @objc private func addToSplitMenu(_ s: NSMenuItem) { addToSplit(s.tag) }
    @objc private func removeFromSplitMenu(_ s: NSMenuItem) { removeFromSplit(s.tag) }

    /// Address field + nav-button state reflect the active tab.
    private func updateChrome() {
        addressField.stringValue = activeWebView.url?.absoluteString ?? ""
        backButton.isEnabled = activeWebView.canGoBack
        forwardButton.isEnabled = activeWebView.canGoForward
        updateShieldIcon()
        updateTranslateIcon()
    }

    // MARK: - Translate (on-device)

    /// Reflect the active page's translated state on the toolbar button.
    private func updateTranslateIcon() {
        let wv = activeWebView
        wv.evaluateJavaScript(PageTranslationScript.isTranslated) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self, self.activeWebView === wv else { return }
                let on = (result as? Bool) ?? false
                self.translateButton.image = NSImage(systemSymbolName: on ? "character.book.closed.fill" : "translate",
                                                     accessibilityDescription: "Translate Page")?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
                let tint: NSColor = on ? .controlAccentColor : .secondaryLabelColor
                self.translateButton.restingTint = tint
                self.translateButton.contentTintColor = tint
                self.translateButton.toolTip = on ? "Show Original" : "Translate Page"
            }
        }
    }

    @objc func translateButtonClicked() {
        let wv = activeWebView
        wv.evaluateJavaScript(PageTranslationScript.isTranslated) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if (result as? Bool) ?? false { self.revertActivePage() }
                else { self.translateActivePage() }
            }
        }
    }

    /// Restore the page's original text.
    private func revertActivePage() {
        activeWebView.evaluateJavaScript(PageTranslationScript.revert) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateTranslateIcon() }
        }
    }

    /// Extract the page's text, detect its language, translate on-device into the preferred website
    /// language, and reinject. No page content leaves the machine.
    func translateActivePage() {
        let wv = activeWebView
        let targetCode = AppSettings.websiteLanguage.isEmpty ? "en" : AppSettings.websiteLanguage
        wv.evaluateJavaScript(PageTranslationScript.extract) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let items = try? JSONDecoder().decode([TextNode].self, from: data),
                      !items.isEmpty else {
                    self.showToast("Nothing to translate on this page"); return
                }
                let texts = items.map { $0.text }
                // Detect the page language from a sample; skip if it's already the target.
                let sample = texts.prefix(40).joined(separator: " ")
                let detected = PageTranslator.detectLanguage(sample)
                if let detected, Locale.Language(identifier: detected).languageCode?.identifier
                    == Locale.Language(identifier: targetCode).languageCode?.identifier {
                    let name = Locale.current.localizedString(forLanguageCode: targetCode) ?? "that language"
                    self.showToast("This page is already in \(name.capitalized)")
                    return
                }
                self.showToast("Translating…", record: false)
                Task { @MainActor in
                    do {
                        let translated = try await PageTranslator.shared.translate(texts, to: targetCode, from: detected)
                        guard self.activeWebView === wv else { return }   // tab switched away
                        let pairs = zip(items, translated).map { ["id": $0.id, "t": $1] as [String: Any] }
                        let pdata = try JSONSerialization.data(withJSONObject: pairs)
                        let pjson = String(decoding: pdata, as: UTF8.self)
                        wv.evaluateJavaScript(PageTranslationScript.reinject(pairsJSON: pjson)) { _, _ in
                            MainActor.assumeIsolated { self.updateTranslateIcon() }
                        }
                        let from = detected.flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? "the page"
                        self.showToast("Translated from \(from.capitalized)")
                    } catch PageTranslator.TranslateError.unsupported(let lang) {
                        self.showToast("Translation for \(lang.capitalized) isn't available on this Mac")
                    } catch {
                        self.showToast("Couldn't translate this page")
                    }
                }
            }
        }
    }

    /// Decoded shape of a `PageTranslationScript.extract` entry.
    private struct TextNode: Decodable { let id: Int; let text: String }

    // MARK: - Reminders (EventKit)

    /// Open the Tools sidebar and show the Reminders tool.
    func revealRemindersTool() {
        if !toolsOpen { setToolsOpen(true, animated: true) }
        toolsSidebar.selectTool("reminders")
    }

    /// Ensure Reminders access, then run `body`. Surfaces a toast if declined.
    private func withReminders(_ body: @escaping () -> Void) {
        let svc = RemindersService.shared
        if svc.authorized { body(); return }
        Task { @MainActor in
            if await svc.requestAccess() { body() }
            else { self.showToast("Muninn needs Reminders access — enable it in System Settings › Privacy & Security › Reminders") }
        }
    }

    /// Quick add: prompt for text, add to the default list.
    private func newReminder() {
        withReminders { [weak self] in
            guard let self, let title = self.promptForText(title: "New Reminder", message: "Reminder:", initial: "") else { return }
            do {
                try RemindersService.shared.createReminder(title: title, inListId: RemindersService.shared.defaultListId())
                self.showToast("Reminder added")
                self.revealRemindersTool()
            } catch { self.showToast("Couldn't add the reminder") }
        }
    }

    /// Add the current page (title + URL) as a reminder — a "read later" / follow-up.
    private func reminderFromPage() {
        let title = activeTab.displayTitle.isEmpty ? (activeWebView.url?.host ?? "Page") : activeTab.displayTitle
        let url = activeWebView.url
        withReminders { [weak self] in
            guard let self else { return }
            do {
                try RemindersService.shared.createReminder(title: title, notes: url?.absoluteString, url: url,
                                                           inListId: RemindersService.shared.defaultListId())
                self.showToast("Saved “\(title)” to Reminders")
                self.revealRemindersTool()
            } catch { self.showToast("Couldn't save to Reminders") }
        }
    }

    /// Turn the current page into a new Reminders list. Structured schema.org/Recipe data first
    /// (ingredients or steps); if none, fall back to the local model. Fully on-device.
    private func listFromPage() {
        let wv = activeWebView
        withReminders { [weak self] in
            guard let self else { return }
            wv.evaluateJavaScript(PageListExtractor.script) { [weak self] result, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let json = result as? String,
                       let recipe = PageListExtractor.decode(json), recipe.hasStructuredData {
                        self.buildListFromRecipe(recipe)
                    } else {
                        self.buildListFromModel()   // no structured data → local model
                    }
                }
            }
        }
    }

    /// Structured path: if both ingredients and steps exist, ask which; otherwise use what's present.
    private func buildListFromRecipe(_ recipe: PageListExtractor.Recipe) {
        var items = recipe.ingredients
        if !recipe.ingredients.isEmpty && !recipe.steps.isEmpty {
            let a = NSAlert()
            a.messageText = "Create list from “\(recipe.listName)”"
            a.informativeText = "This page has both ingredients and steps. Which should the list contain?"
            a.addButton(withTitle: "Ingredients")
            a.addButton(withTitle: "Steps")
            a.addButton(withTitle: "Cancel")
            switch a.runModal() {
            case .alertFirstButtonReturn:  items = recipe.ingredients
            case .alertSecondButtonReturn: items = recipe.steps
            default: return
            }
        } else if recipe.ingredients.isEmpty {
            items = recipe.steps
        }
        createList(named: recipe.listName, items: items)
    }

    /// Fallback path: ask the local model to extract a `{name, items}` list from the page text.
    private func buildListFromModel() {
        guard !OllamaSettings.defaultModel.isEmpty, let base = OllamaSettings.baseURLValue else {
            showToast("No list data on this page. Configure a local model (Settings → Models) to extract one.")
            return
        }
        showToast("Reading the page…", record: false)
        currentPageText { [weak self] title, url, text in
            guard let self else { return }
            let prompt = """
            From the web page below, extract the list a person would want as reminders — e.g. recipe \
            ingredients, shopping items, a checklist, or steps. Respond with ONLY JSON, no prose:
            {"name": "<short list name>", "items": ["item one", "item two"]}

            Title: \(title)
            URL: \(url)

            \(text)
            """
            let client = OllamaClient(baseURL: base)
            self.askTask?.cancel()
            self.askTask = Task { @MainActor in
                var raw = ""
                do { for try await tok in client.generateStream(model: OllamaSettings.defaultModel, prompt: prompt) { raw += tok } }
                catch { self.showToast("Couldn't reach the local model"); return }
                guard let list = PageListExtractor.decodeModelList(raw) else {
                    self.showToast("Couldn't find a list on this page"); return
                }
                self.createList(named: list.name, items: list.items)
            }
        }
    }

    /// Create a new Reminders list and populate it, then reveal the tool focused on it.
    private func createList(named name: String, items: [String]) {
        let clean = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { showToast("Nothing to add to a list"); return }
        let listName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New List" : name
        do {
            let id = try RemindersService.shared.createList(named: listName)
            let n = try RemindersService.shared.addReminders(clean, toListId: id)
            revealRemindersTool()
            remindersTool.focusList(id: id)
            showToast("Created “\(listName)” with \(n) item\(n == 1 ? "" : "s")")
        } catch { showToast("Couldn't create the list") }
    }

    // MARK: - Shields

    private func applyShields(to tab: BrowserTab) {
        let ucc = tab.webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        if let list = shields.ruleList { ucc.add(list) }
    }
    private func applyShieldsToAllTabs() { tabs.forEach { applyShields(to: $0) } }

    private func updateShieldIcon() {
        let up = shields.shieldsUp(for: activeWebView.url?.host)
        shieldButton.image = NSImage(systemSymbolName: up ? "shield.lefthalf.filled" : "shield.slash", accessibilityDescription: "Shields")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        let tint: NSColor = up ? .secondaryLabelColor : .systemOrange
        shieldButton.restingTint = tint          // survives hover-exit
        shieldButton.contentTintColor = tint
    }

    @objc private func showShieldsPanel() {
        let panel = ShieldsPanelController()
        panel.host = activeWebView.url?.host
        panel.onToggled = { [weak self] in self?.activeWebView.reload(); self?.updateShieldIcon() }
        panel.onOpenSettings = { [weak self] in self?.openSettings() }
        let pop = NSPopover()
        pop.contentViewController = panel
        pop.behavior = .transient
        pop.show(relativeTo: shieldButton.bounds, of: shieldButton, preferredEdge: .maxY)
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

        if !favs.isEmpty || !pins.isEmpty || !wsFolders.isEmpty {
            tabStack.addArrangedSubview(separatorLine(showClear: !regs.isEmpty))
        }
        // Regular tabs — a split group renders once as a combined chip at its first member.
        var renderedGroups = Set<UUID>()
        for (i, tab) in regs {
            if let gid = tab.splitGroupId {
                if renderedGroups.contains(gid) { continue }
                renderedGroups.insert(gid)
                let members = regs.filter { $0.element.splitGroupId == gid }.map { $0.offset }
                tabStack.addArrangedSubview(makeSplitChip(members))
            } else {
                tabStack.addArrangedSubview(makeTabChip(tab, index: i, active: i == activeIndex))
            }
        }
        tabStack.addArrangedSubview(newTabRow())
    }

    /// A split group as one combined sidebar tab: a bordered row of per-member mini-chips.
    private func makeSplitChip(_ memberIndices: [Int]) -> NSView {
        let isActiveGroup = memberIndices.contains(activeIndex)
        let group = NSView()
        group.wantsLayer = true
        group.layer?.cornerRadius = 7
        group.layer?.borderWidth = 1
        group.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(isActiveGroup ? 0.7 : 0.3).cgColor
        group.layer?.backgroundColor = (isActiveGroup ? NSColor.controlAccentColor.withAlphaComponent(0.12) : .clear).cgColor
        group.translatesAutoresizingMaskIntoConstraints = false
        group.widthAnchor.constraint(equalToConstant: sidebarWidth - 16).isActive = true
        group.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 3
        row.translatesAutoresizingMaskIntoConstraints = false
        for i in memberIndices { row.addArrangedSubview(makeSplitMember(index: i, active: i == activeIndex)) }
        group.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 3),
            row.trailingAnchor.constraint(equalTo: group.trailingAnchor, constant: -3),
            row.topAnchor.constraint(equalTo: group.topAnchor, constant: 3),
            row.bottomAnchor.constraint(equalTo: group.bottomAnchor, constant: -3),
        ])
        return group
    }

    /// One member mini-chip inside a combined split chip: favicon + title + × (leaves the split).
    private func makeSplitMember(index: Int, active: Bool) -> NSView {
        let tab = tabs[index]
        let chip = TabChipView()
        chip.index = index
        chip.onSelect = { [weak self] in self?.selectTab(index) }
        chip.menu = tabContextMenu(index)
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 5
        chip.layer?.backgroundColor = (active ? NSColor.controlAccentColor.withAlphaComponent(0.30)
                                              : NSColor.secondaryLabelColor.withAlphaComponent(0.12)).cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false

        let fav = NSImageView()
        fav.imageScaling = .scaleProportionallyDown
        fav.wantsLayer = true; fav.layer?.cornerRadius = 2; fav.layer?.masksToBounds = true
        fav.translatesAutoresizingMaskIntoConstraints = false
        if let icon = tab.favicon { fav.image = icon }
        else {
            fav.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .regular))
            fav.contentTintColor = .tertiaryLabelColor
        }

        let title = NSTextField(labelWithString: tab.displayTitle)
        title.font = .systemFont(ofSize: 10, weight: active ? .semibold : .regular)
        title.textColor = active ? .labelColor : .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let close = HoverCloseButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove from split")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .semibold)) ?? NSImage(),
                                     target: self, action: #selector(closePaneButton(_:)))
        close.tag = tab.id
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.translatesAutoresizingMaskIntoConstraints = false

        chip.addSubview(fav); chip.addSubview(title); chip.addSubview(close)
        NSLayoutConstraint.activate([
            fav.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 6),
            fav.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            fav.widthAnchor.constraint(equalToConstant: 13),
            fav.heightAnchor.constraint(equalToConstant: 13),
            title.leadingAnchor.constraint(equalTo: fav.trailingAnchor, constant: 5),
            title.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            close.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 3),
            close.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -5),
            close.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 14),
            close.heightAnchor.constraint(equalToConstant: 14),
        ])
        return chip
    }

    /// Wrap an indented chip so it sits inset under a folder header while the row still
    /// spans the sidebar width (keeps the leading-aligned stack tidy).
    private func indentWrap(_ chip: NSView, by inset: CGFloat) -> NSView {
        let c = NSView()
        c.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(chip)
        NSLayoutConstraint.activate([
            c.widthAnchor.constraint(equalToConstant: sidebarWidth - 16),
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
        row.onDrop = { [weak self] payload, zone in
            guard let self else { return }
            switch payload {
            case .tab(let id): // drop a tab onto the header → into this folder (at top)
                self.moveTab(id, kind: .pinned, folderId: folder.id,
                             nextTo: self.firstTabId(kind: .pinned, folderId: folder.id), before: true)
            case .folder(let fid): // drop a folder onto the header → reorder folders
                self.moveFolder(fid, nextTo: folder.id, before: zone != .after)
            }
        }
        row.wantsLayer = true
        row.layer?.cornerRadius = 7
        row.layer?.backgroundColor = bg.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: sidebarWidth - 16).isActive = true
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
        row.dropSupportsOnto = false
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: sidebarWidth - 16).isActive = true
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

    /// The line between pinned/favourites and regular tabs, with a small "Clear" button on the
    /// right (↓ = the unpinned tabs below) that closes all unpinned tabs.
    private func separatorLine(showClear: Bool) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: sidebarWidth - 16).isActive = true
        row.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(box)

        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            box.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        if showClear {
            let clear = NSButton(title: "Clear",
                                 image: NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "Clear unpinned tabs")!
                                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))!,
                                 target: self, action: #selector(clearUnpinnedTabs))
            clear.imagePosition = .imageLeading
            clear.isBordered = false
            clear.font = .systemFont(ofSize: 10, weight: .medium)
            clear.contentTintColor = .secondaryLabelColor
            clear.toolTip = "Clear unpinned tabs"
            clear.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(clear)
            NSLayoutConstraint.activate([
                clear.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                clear.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                box.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -8),
            ])
        } else {
            box.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        }
        return row
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
        // Hover to glance: a live preview popover of the site.
        icon.onHover = { [weak self, weak icon] inside in
            guard let self, let icon else { return }
            if inside { self.schedulePreview(for: index, from: icon) } else { self.scheduleClosePreview() }
        }
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
        icon.toolTip = tab.displayTitle
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
        chip.widthAnchor.constraint(equalToConstant: sidebarWidth - 16 - inset).isActive = true
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

        let title = NSTextField(labelWithString: tab.displayTitle)
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
        addressField.delegate = self // inline history autocomplete
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.font = .systemFont(ofSize: 13)
        // Force single line: no wrapping, clip long URLs, scroll horizontally while editing.
        addressField.usesSingleLineMode = true
        addressField.maximumNumberOfLines = 1
        addressField.lineBreakMode = .byTruncatingTail
        addressField.cell?.wraps = false
        addressField.cell?.isScrollable = true

        // Share button — inside the URL box, opens the macOS share sheet for the current page.
        configureIconButton(shareButton, symbol: "square.and.arrow.up",
                            action: #selector(shareCurrentURL(_:)), tip: "Share…")

        // Shields + Settings — their own cluster, right of the nav cluster (divider between).
        configureIconButton(shieldButton, symbol: "shield.lefthalf.filled",
                            action: #selector(showShieldsPanel), tip: "Shields")
        configureIconButton(settingsButton, symbol: "gearshape",
                            action: #selector(showSettingsMenu(_:)), tip: "Settings")
        // Translate — on-device page translation (no text leaves the Mac).
        configureIconButton(translateButton, symbol: "translate",
                            action: #selector(translateButtonClicked), tip: "Translate Page")

        // Browser-extension action buttons — on the address row (full width, no traffic-light
        // offset), so a variable number of extension icons never overflows the narrow top strip.
        extensionBar.orientation = .horizontal
        extensionBar.spacing = 2
        extensionBar.alignment = .centerY
        extensionBar.translatesAutoresizingMaskIntoConstraints = false

        // Vertical divider separating the nav cluster from the shield/settings cluster.
        let toolbarDivider = NSBox(); toolbarDivider.boxType = .separator
        toolbarDivider.translatesAutoresizingMaskIntoConstraints = false

        // Top bar: [toggle back forward reload | shield settings]
        let topBar = NSStackView(views: [toggleButton, backButton, forwardButton, reloadButton,
                                         toolbarDivider, shieldButton, translateButton, settingsButton])
        topBar.orientation = .horizontal
        topBar.spacing = 2
        topBar.alignment = .centerY
        topBar.setCustomSpacing(7, after: reloadButton)   // breathing room around the divider
        topBar.setCustomSpacing(7, after: toolbarDivider)
        topBar.setHuggingPriority(.required, for: .horizontal) // size to content, never compress
        topBar.translatesAutoresizingMaskIntoConstraints = false

        // Left sidebar: top bar + address field + vertical tab list, collapsible.
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

        sidebar.addSubview(topBar)
        sidebar.addSubview(addressField) // Arc-style: URL bar in the sidebar, under the top bar
        sidebar.addSubview(extensionBar) // extension icons on the address row, left of Share
        sidebar.addSubview(shareButton)  // inside the URL box, right edge
        // Library button — bottom-left, beside the workspace switcher.
        libraryButton.image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "Library")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        libraryButton.isBordered = false
        libraryButton.restingTint = .secondaryLabelColor
        libraryButton.contentTintColor = .secondaryLabelColor
        libraryButton.target = self; libraryButton.action = #selector(openLibrary)
        libraryButton.toolTip = "Library — downloads & media"
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(libraryButton)
        sidebar.addSubview(workspaceBar)
        sidebar.addSubview(workspaceHoverLabel)
        sidebar.addSubview(tabStack)
        NSLayoutConstraint.activate([
            toolbarDivider.heightAnchor.constraint(equalToConstant: 18),
            topBar.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 6),
            topBar.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 76), // clear of the traffic lights
            // no trailing constraint: the bar keeps its intrinsic size (never compresses/overlaps)
            addressField.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            addressField.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            addressField.trailingAnchor.constraint(equalTo: extensionBar.leadingAnchor, constant: -4),
            extensionBar.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -4),
            extensionBar.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
            shareButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            shareButton.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
            tabStack.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 12),
            tabStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            tabStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            libraryButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            libraryButton.centerYAnchor.constraint(equalTo: workspaceBar.centerYAnchor),
            libraryButton.widthAnchor.constraint(equalToConstant: 28),
            libraryButton.heightAnchor.constraint(equalToConstant: 28),
            workspaceBar.leadingAnchor.constraint(equalTo: libraryButton.trailingAnchor, constant: 8),
            workspaceBar.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -10),
            workspaceBar.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -12),
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

        // Right Tools sidebar — flush to the right edge, framing the web card (mirrors left).
        toolsSidebar.translatesAutoresizingMaskIntoConstraints = false
        toolsSidebar.isHidden = true

        // Tools toggle — top-right, in the transparent title-bar strip.
        configureButton(toolsButton, symbol: "sidebar.right", action: #selector(toggleToolsSidebar))
        toolsButton.toolTip = "Tools"

        let content = NSView()
        content.wantsLayer = true // holds the workspace tint behind the floating card
        content.addSubview(webContainer)
        content.addSubview(toolsSidebar)   // right edge, behind the web card's shadow
        content.addSubview(sidebar)        // above the web card
        content.addSubview(toolsButton)
        content.addSubview(sidebarSplitter) // draggable resize handles on the pane edges
        content.addSubview(toolsSplitter)
        window.contentView = content

        sidebarLeadingConstraint = sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 0)
        webLeadingDocked = webContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: Self.webCardInset)
        webLeadingFull = webContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.webCardInset)
        // Web card right edge: window edge (tools hidden) vs the tools sidebar (tools shown).
        webTrailingCollapsed = webContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.webCardInset)
        webTrailingWithTools = webContainer.trailingAnchor.constraint(equalTo: toolsSidebar.leadingAnchor, constant: -Self.webCardInset)
        sidebarWidthConstraint = sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth)
        toolsWidthConstraint = toolsSidebar.widthAnchor.constraint(equalToConstant: toolsWidth)
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarWidthConstraint,
            sidebarLeadingConstraint,
            webContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.webCardTopInset),
            webContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.webCardInset),
            webLeadingDocked, // active while pinned open (the default)
            webTrailingCollapsed, // tools hidden by default
            toolsSidebar.topAnchor.constraint(equalTo: content.topAnchor),
            toolsSidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            toolsSidebar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolsWidthConstraint,
            toolsButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            toolsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
        ])

        // Resize handles: a thin draggable strip centred on each pane's inner edge.
        sidebarSplitter.translatesAutoresizingMaskIntoConstraints = false
        toolsSplitter.translatesAutoresizingMaskIntoConstraints = false
        sidebarSplitter.onDrag = { [weak self] dx in self?.resizeSidebar(by: dx) }
        sidebarSplitter.onDragEnd = { [weak self] in self?.rebuildTabBar(); self?.persist() }
        toolsSplitter.onDrag = { [weak self] dx in self?.resizeTools(by: -dx) }
        toolsSplitter.onDragEnd = { [weak self] in self?.persist() }
        toolsSplitter.isHidden = true   // tools sidebar starts hidden
        NSLayoutConstraint.activate([
            sidebarSplitter.topAnchor.constraint(equalTo: content.topAnchor),
            sidebarSplitter.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarSplitter.centerXAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarSplitter.widthAnchor.constraint(equalToConstant: 8),
            toolsSplitter.topAnchor.constraint(equalTo: content.topAnchor),
            toolsSplitter.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            toolsSplitter.centerXAnchor.constraint(equalTo: toolsSidebar.leadingAnchor),
            toolsSplitter.widthAnchor.constraint(equalToConstant: 8),
        ])
        // Peek: leaving the floating sidebar slides it back (only while collapsed).
        sidebar.onExited = { [weak self] in self?.closePeek() }
        rebuildTabBar()

        // Live Calendar tool (Tools sidebar).
        liveWidget.onJoin = { [weak self] url in
            self?.openRouted(url, newTab: true)
            self?.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
        askChat.runChat = { [weak self] messages, onToken, onDone in
            self?.runChatTurn(messages, onToken: onToken, onDone: onDone)
        }
        askChat.fetchPageContext = { [weak self] completion in
            guard let self else { completion(nil); return }
            self.currentPageText { title, url, text in completion(.init(title: title, url: url, text: text)) }
        }
        notificationsView.onClear = { [weak self] in self?.notificationStore.clear() }
        notificationStore.onChange = { [weak self] in
            guard let self else { return }
            self.notificationsView.reload(self.notificationStore.items)
        }
        notificationsView.reload(notificationStore.items)
        rebuildTools()
    }

    /// Drop expired notifications and refresh the view.
    private func pruneNotifications() {
        notificationStore.prune()
        notificationsView.reload(notificationStore.items)
    }

    /// Register the Tools-sidebar tools (Calendar / Ask / Notifications). Keeps the selection.
    private func rebuildTools() {
        toolsSidebar.setTools([
            .init(id: "calendar", title: "Calendar", symbol: "calendar", view: liveWidget),
            .init(id: "reminders", title: "Reminders", symbol: "checklist", view: remindersTool),
            .init(id: "ask", title: "Ask", symbol: "sparkles", view: askChat),
            .init(id: "notifications", title: "Notifications", symbol: "bell", view: notificationsView),
        ])
    }

    // MARK: - Live Calendar

    /// Start the feed + the 1 s countdown tick (called once, after the window is up).
    private func startLiveCalendar() {
        calendarFeed.onUpdate = { [weak self] in self?.resolveCalendar() }
        calendarFeed.setCalendars(liveCalendars)
        calendarFeed.start(interval: 300)
        calendarTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickCalendar() }
        }
        resolveCalendar()
    }

    /// Recompute the next occurrence (cheap-ish; runs on feed refresh + when one ends).
    private func resolveCalendar() {
        currentOccurrence = calendarFeed.nextOccurrence(now: Date())
        refreshLiveWidget()
    }

    /// Per-second update: advance to the next event once the current one ends, else re-render
    /// the countdown from the cached occurrence.
    private func tickCalendar() {
        guard toolsOpen, !liveCalendars.isEmpty else { return }
        if let occ = currentOccurrence, Date() >= occ.end { resolveCalendar() } else { refreshLiveWidget() }
    }

    private func refreshLiveWidget() {
        let lead = liveCalendars.first { $0.id == currentOccurrence?.event.calendarId }?.leadTimeMinutes ?? 5
        liveWidget.update(occurrence: currentOccurrence, leadTimeMinutes: lead, now: Date())
    }

    /// Called by Settings when the calendar list changes.
    private func liveCalendarsChanged() {
        calendarFeed.setCalendars(liveCalendars)
        resolveCalendar()
        persist()
    }

    // Settings API (Settings → Calendars).
    func settingsLiveCalendars() -> [LiveCalendar] { liveCalendars }
    func settingsAddCalendar() { liveCalendars.append(LiveCalendar(name: "Calendar")); liveCalendarsChanged() }
    func settingsRemoveCalendar(_ id: UUID) { liveCalendars.removeAll { $0.id == id }; liveCalendarsChanged() }
    func settingsUpdateCalendar(_ id: UUID, _ mutate: (inout LiveCalendar) -> Void) {
        guard let i = liveCalendars.firstIndex(where: { $0.id == id }) else { return }
        mutate(&liveCalendars[i]); liveCalendarsChanged()
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        window.acceptsMouseMovedEvents = true
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .otherMouseDown]) { [weak self] e in
            guard let self else { return e }
            if e.type == .mouseMoved { self.handleMouseMoved(e); return e }
            return self.handleOtherMouse(e)
        }
    }

    /// While collapsed, reveal the sidebar when the cursor reaches the left edge.
    private func handleMouseMoved(_ e: NSEvent) {
        guard !sidebarOpen, !peeking, let content = window.contentView else { return }
        let x = content.convert(e.locationInWindow, from: nil).x
        if x <= 4 { openPeek() }
    }

    /// Mouse extra buttons: side buttons 3/4 → back/forward on the active tab; middle-click (2) on
    /// the back/forward/reload buttons → perform that action in a new tab, keeping the current one.
    private func handleOtherMouse(_ e: NSEvent) -> NSEvent? {
        guard e.window === window else { return e }
        switch e.buttonNumber {
        case 2:
            return middleClickNav(e) ? nil : e
        case 3:
            if activeWebView.canGoBack { activeWebView.goBack() }
            return nil
        case 4:
            if activeWebView.canGoForward { activeWebView.goForward() }
            return nil
        default:
            return e
        }
    }

    /// Middle-click on a nav button opens its target in a background tab (current tab untouched).
    private func middleClickNav(_ e: NSEvent) -> Bool {
        func over(_ b: NSView) -> Bool { b.bounds.contains(b.convert(e.locationInWindow, from: nil)) }
        if over(backButton), let u = activeWebView.backForwardList.backItem?.url { openInBackgroundTab(u); return true }
        if over(forwardButton), let u = activeWebView.backForwardList.forwardItem?.url { openInBackgroundTab(u); return true }
        if over(reloadButton), let u = activeWebView.url ?? activeTab.currentURL { openInBackgroundTab(u); return true }
        return false
    }

    /// Open a URL in a new tab WITHOUT switching to it (the current tab stays active).
    private func openInBackgroundTab(_ url: URL) {
        let tab = makeTab(); tab.workspaceId = activeWorkspaceId
        tabs.append(tab); extensionBridge.didOpen(tab)
        tab.load(url)
        rebuildTabBar()
    }

    // MARK: - Resizable panes

    private func resizeSidebar(by dx: CGFloat) {
        let w = min(max(sidebarWidth + dx, Self.sidebarWidthRange.lowerBound), Self.sidebarWidthRange.upperBound)
        guard w != sidebarWidth else { return }
        sidebarWidth = w
        sidebarWidthConstraint.constant = w
    }

    private func resizeTools(by dx: CGFloat) {
        let w = min(max(toolsWidth + dx, Self.toolsWidthRange.lowerBound), Self.toolsWidthRange.upperBound)
        guard w != toolsWidth else { return }
        toolsWidth = w
        toolsWidthConstraint.constant = w
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
        sidebarSplitter.isHidden = true // don't resize a floating peek
        setSidebarFloating(true) // rounded + shadowed while revealed
        updateTrafficLights()
        slideSidebar(to: 0)
    }
    private func closePeek() {
        guard peeking else { return }
        peeking = false
        slideSidebar(to: -sidebarWidth) { [weak self] in self?.updateTrafficLights() }
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
        sidebarSplitter.isHidden = !sidebarOpen   // no resize handle while collapsed
        setSidebarFloating(false) // docked (or collapsed): flush + no shadow
        webLeadingDocked.isActive = sidebarOpen   // docked: web sits beside the sidebar
        webLeadingFull.isActive = !sidebarOpen     // collapsed: web fills the width
        if sidebarOpen { updateTrafficLights() }   // reveal immediately when opening
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            sidebarLeadingConstraint.animator().constant = sidebarOpen ? 0 : -sidebarWidth
            window.contentView?.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            self?.updateTrafficLights() // hide after the collapse finishes
        })
    }

    @objc private func toggleToolsSidebar() { setToolsOpen(!toolsOpen, animated: true) }

    private func setToolsOpen(_ open: Bool, animated: Bool) {
        toolsOpen = open
        toolsSidebar.isHidden = !open
        toolsSplitter.isHidden = !open
        webTrailingCollapsed.isActive = !open
        webTrailingWithTools.isActive = open
        toolsButton.restingTint = open ? .controlAccentColor : .labelColor
        toolsButton.contentTintColor = open ? .controlAccentColor : .labelColor
        let apply = { self.window.contentView?.layoutSubtreeIfNeeded() }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                apply()
            }
        } else { apply() }
        if open { resolveCalendar() } // refresh the widget immediately on reveal
        persist()
    }

    private func configureButton(_ b: NSButton, symbol: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        b.isBordered = false                 // no bezel — crisp symbol on the tinted bar
        b.contentTintColor = .labelColor      // high-contrast (adapts light/dark), not accent blue
        if let h = b as? HoverIconButton { h.restingTint = .labelColor }
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 24).isActive = true
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    /// A subtler icon button (resting secondary tint, hover brightens) for the shield/settings cluster.
    private func configureIconButton(_ b: HoverIconButton, symbol: String, action: Selector, tip: String) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        b.isBordered = false
        b.restingTint = .secondaryLabelColor
        b.contentTintColor = .secondaryLabelColor
        b.target = self; b.action = action
        b.toolTip = tip
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 24).isActive = true
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            // Only handle main-window shortcuts when the main window is focused — a Quick
            // Look window has its own key handling.
            guard self.window.isKeyWindow else { return e }
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Control+Number → switch to workspace N (Arc-style; fixed, not remappable).
            if flags == .control, let ch = e.charactersIgnoringModifiers, let n = Int(ch), n >= 1 {
                if n <= self.workspaces.count { self.switchWorkspace(to: self.workspaces[n - 1].id) }
                return nil
            }
            let masked = flags.intersection(Shortcut.mask).rawValue
            let key = (e.charactersIgnoringModifiers ?? "").lowercased()
            // Developer Mode: ⌥⌘I inspect, ⌥⌘U view source (fixed; active only in dev mode).
            if AppSettings.developerMode, flags.intersection(Shortcut.mask) == [.command, .option] {
                if key == "i" { self.inspectActiveTab(); return nil }
                if key == "u" { self.viewSource(of: self.activeWebView); return nil }
            }
            // Remappable shortcuts (Settings → Shortcuts).
            if let action = ShortcutStore.action(key: key, modifiers: masked) {
                self.perform(action); return nil
            }
            return e
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .commandBar:    openCommandPalette()
        case .newTab:        newTab()
        case .quickLook:     openQuickLook(nil)
        case .closeTab:      closeActiveTab()
        case .reopenClosed:  reopenLastClosed()
        case .togglePin:     togglePinActive()
        case .focusAddress:  window.makeFirstResponder(addressField)
        case .reload:        reload()
        case .copyURL:       copyActiveURL()
        case .copyMarkdown:  copyActiveMarkdown()
        case .clearUnpinned: clearUnpinnedTabs()
        case .settings:      openSettings()
        case .toolsSidebar:  toggleToolsSidebar()
        }
    }

    // MARK: - actions (active tab)

    private func navigate(to string: String) {
        let s = string.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        // URL-like → open it; otherwise search with the configured engine.
        let looksURL = !s.contains(" ") && (s.contains("://") || (s.contains(".") && !s.hasSuffix(".")))
        if looksURL {
            let full = s.contains("://") ? s : "https://" + s
            if let url = URL(string: full) { openRouted(url, newTab: false); return }
        }
        activeTab.load(currentSearchEngine.url(s))
    }

    @objc private func addressSubmitted() { navigate(to: addressField.stringValue) }
    @objc private func goBack() { activeWebView.goBack() }
    @objc private func goForward() { activeWebView.goForward() }
    @objc private func reload() { activeWebView.reload() }

    /// Open the macOS share sheet for the current page, anchored to the share button.
    @objc private func shareCurrentURL(_ sender: NSView) {
        guard let url = activeWebView.url ?? activeTab.currentURL else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    /// A quick fade + slight rise on the freshly shown web content, so opening a tab feels smooth.
    private func animateTabOpen() {
        let v = activeWebView
        v.wantsLayer = true
        v.alphaValue = 0
        v.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: 6))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            v.animator().alphaValue = 1
            v.layer?.setAffineTransform(.identity)
        }
    }

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

extension AppShell: NSTextFieldDelegate {
    /// Inline autocomplete: as you type in the address bar, complete to the best history host
    /// (e.g. "you" → "youtube.com") with the suffix selected. Tab / → accepts it.
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === addressField, suggestionsEnabled else { return }
        if skipAddressComplete { skipAddressComplete = false; return }
        guard let editor = addressField.currentEditor() else { return }
        let text = addressField.stringValue
        let len = (text as NSString).length
        let sel = editor.selectedRange
        // Only when typing forward at the very end (not mid-string, not with a selection).
        guard sel.length == 0, sel.location == len, !text.isEmpty else { return }
        guard let completion = currentHistory.bestCompletion(for: text),
              (completion as NSString).length > len else { return }
        addressField.stringValue = completion
        editor.selectedRange = NSRange(location: len, length: (completion as NSString).length - len)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === addressField else { return false }
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
            skipAddressComplete = true // don't re-suggest while deleting
            return false
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveRight(_:)):
            // Accept a pending completion by collapsing the selection to the end.
            if let editor = control.currentEditor(), editor.selectedRange.length > 0 {
                let end = (addressField.stringValue as NSString).length
                editor.selectedRange = NSRange(location: end, length: 0)
                return true
            }
            return false
        default:
            return false
        }
    }
}

extension AppShell: @preconcurrency NSSharingServicePickerDelegate {
    /// Release the pinned toast once the share sheet is dismissed (service chosen or not).
    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        toastPinned = false
        dismissToast(currentToast)
    }
}

// MARK: - Browser extensions host

extension AppShell: ExtensionHost {
    var extNSWindow: NSWindow { window }
    func extLiveTabs() -> [BrowserTab] { tabs.filter { $0.workspaceId == activeWorkspaceId } }
    func extActiveTab() -> BrowserTab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }

    func extOpenTab(url: URL?) -> BrowserTab {
        let tab = makeTab(); tab.workspaceId = activeWorkspaceId
        tabs.append(tab); extensionBridge.didOpen(tab); activeIndex = tabs.count - 1
        showActiveWebView()
        if let url { tab.load(url) } else { loadLanding(tab) }
        rebuildTabBar()
        return tab
    }
    func extActivate(_ tab: BrowserTab) { if let i = tabs.firstIndex(where: { $0 === tab }) { selectTab(i) } }
    func extCloseTab(_ tab: BrowserTab) { if let i = tabs.firstIndex(where: { $0 === tab }) { closeTab(i) } }

    /// Show an extension's popup anchored to its toolbar button (falls back to the gear).
    func extPresentActionPopover(_ popover: NSPopover, for context: WKWebExtensionContext) {
        let anchor = extActionButtons.first(where: { $0.value === context })?.key ?? settingsButton
        popover.behavior = .transient   // dismiss on click-outside / Esc
        if popover.contentSize.width < 80 || popover.contentSize.height < 80 {
            popover.contentSize = NSSize(width: 380, height: 600)
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
}
