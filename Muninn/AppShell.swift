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
    private var quickLooks: [QuickLookWindow] = []
    private var nextQuickLookId = 0
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
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let settingsButton = NSButton()
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
    // Right-side Tools sidebar (hosts the Live Calendar).
    private let toolsSidebar = ToolsSidebar()
    private let toolsButton = NSButton()
    private var toolsOpen = false
    private var webTrailingCollapsed: NSLayoutConstraint!
    private var webTrailingWithTools: NSLayoutConstraint!
    private static let toolsWidth: CGFloat = 280
    // Live Calendar (first Tools-sidebar tool).
    private var liveCalendars: [LiveCalendar] = []
    private let calendarFeed = CalendarFeed()
    private let liveWidget = LiveCalendarWidget()
    private var currentOccurrence: Occurrence?
    private var calendarTick: Timer?
    private var mouseMonitor: Any?
    private var archiveTimer: Timer?
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

        // Profiles — ensure a default; it keeps the shared store so existing logins survive.
        profiles = saved.profiles.isEmpty ? [Profile(name: "Personal", colorIndex: 1)] : saved.profiles
        defaultProfileId = profiles[0].id
        let profileIds = Set(profiles.map { $0.id })
        routingRules = saved.routingRules
        liveCalendars = saved.liveCalendars

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
        // Auto-Archive sweep every few minutes (also runs on each tab switch).
        archiveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.archiveStaleTabs() }
        }
        startLiveCalendar()
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
        activeIndex = tabs.count - 1
        popOutIfPlaying(outgoing) // Cmd+T while a video plays → Mini Player
        showActiveWebView()
        rebuildTabBar()
        loadLanding(activeTab)
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
        tab.webView.loadHTMLString(html, baseURL: URL(string: engine.searchBase))
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
                                liveCalendars: liveCalendars))
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
            fresh.setInitialTitle(old.title)
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
        tabs.append(tab); activeIndex = tabs.count - 1
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
    private func showToast(_ message: String, share items: [Any] = []) {
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
        tabs.append(tab); activeIndex = tabs.count - 1
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
        p.searchEngineName = currentSearchEngine.displayName
        p.onClose = { [weak self] in self?.closeCommandPalette() }
        p.onExecute = { [weak self] item in
            guard let self else { return }
            switch item.kind {
            case .tab(let id): if let i = self.tabIndex(id: id) { self.selectTab(i) }
            case .url(let url): self.openRouted(url, newTab: true)
            case .search(let q): self.openInNewTab(currentSearchEngine.url(q))
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

    /// Render whatever the active tab entails — its split group, or itself alone.
    private func showActiveWebView() { showVisibleTabs() }

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
        group.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16).isActive = true
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

        let title = NSTextField(labelWithString: tab.title)
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
        row.dropSupportsOnto = false
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

    /// The line between pinned/favourites and regular tabs, with a small "Clear" button on the
    /// right (↓ = the unpinned tabs below) that closes all unpinned tabs.
    private func separatorLine(showClear: Bool) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 16).isActive = true
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
        addressField.delegate = self // inline history autocomplete
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

        // Settings gear, right of the URL bar.
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.target = self
        settingsButton.action = #selector(showSettingsMenu(_:))
        settingsButton.toolTip = "Settings"
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(navRow)
        sidebar.addSubview(addressField) // Arc-style: URL bar in the sidebar, under nav
        sidebar.addSubview(settingsButton)
        sidebar.addSubview(workspaceBar)
        sidebar.addSubview(workspaceHoverLabel)
        sidebar.addSubview(tabStack)
        NSLayoutConstraint.activate([
            navRow.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 6),
            navRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 88), // clear of the traffic lights
            addressField.topAnchor.constraint(equalTo: navRow.bottomAnchor, constant: 10),
            addressField.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            addressField.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
            settingsButton.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Self.sidebarWidth - 8),
            settingsButton.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 22),
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
        window.contentView = content

        sidebarLeadingConstraint = sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 0)
        webLeadingDocked = webContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: Self.webCardInset)
        webLeadingFull = webContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.webCardInset)
        // Web card right edge: window edge (tools hidden) vs the tools sidebar (tools shown).
        webTrailingCollapsed = webContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.webCardInset)
        webTrailingWithTools = webContainer.trailingAnchor.constraint(equalTo: toolsSidebar.leadingAnchor, constant: -Self.webCardInset)
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            sidebarLeadingConstraint,
            webContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.webCardTopInset),
            webContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.webCardInset),
            webLeadingDocked, // active while pinned open (the default)
            webTrailingCollapsed, // tools hidden by default
            toolsSidebar.topAnchor.constraint(equalTo: content.topAnchor),
            toolsSidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            toolsSidebar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolsSidebar.widthAnchor.constraint(equalToConstant: Self.toolsWidth),
            toolsButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            toolsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
        ])
        // Peek: leaving the floating sidebar slides it back (only while collapsed).
        sidebar.onExited = { [weak self] in self?.closePeek() }
        rebuildTabBar()

        // Live Calendar tool (Tools sidebar).
        liveWidget.onJoin = { [weak self] url in
            self?.openRouted(url, newTab: true)
            self?.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
        toolsSidebar.setTool(liveCalendars.isEmpty ? nil : liveWidget)
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
        toolsSidebar.setTool(liveCalendars.isEmpty ? nil : liveWidget)
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

    @objc private func toggleToolsSidebar() { setToolsOpen(!toolsOpen, animated: true) }

    private func setToolsOpen(_ open: Bool, animated: Bool) {
        toolsOpen = open
        toolsSidebar.isHidden = !open
        webTrailingCollapsed.isActive = !open
        webTrailingWithTools.isActive = open
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
