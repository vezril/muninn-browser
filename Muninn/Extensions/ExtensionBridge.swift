import WebKit
import AppKit

/// The app object the extension bridge queries to see Muninn's tabs/window and to act on them.
/// AppShell conforms; the bridge holds it weakly.
@MainActor
protocol ExtensionHost: AnyObject {
    var extNSWindow: NSWindow { get }
    func extLiveTabs() -> [BrowserTab]        // tabs visible in the active workspace
    func extActiveTab() -> BrowserTab?
    func extOpenTab(url: URL?) -> BrowserTab
    func extActivate(_ tab: BrowserTab)
    func extCloseTab(_ tab: BrowserTab)
    func extPresentActionPopover(_ popover: NSPopover, for context: WKWebExtensionContext)
}

/// Bridges Apple's `WKWebExtension` world to Muninn's tabs/window: it is the controller's delegate
/// (supplying open windows + handling `tabs.create`) and vends stable `WKWebExtensionTab`/`Window`
/// proxies so extension APIs (`tabs.query`, popups, messaging) see the real browser.
@MainActor
final class ExtensionBridge: NSObject, WKWebExtensionControllerDelegate {
    weak var host: ExtensionHost?
    let extWindow = ExtWindow()
    private var tabProxies: [ObjectIdentifier: ExtTab] = [:]

    override init() {
        super.init()
        extWindow.bridge = self
    }

    func proxy(for tab: BrowserTab) -> ExtTab {
        let key = ObjectIdentifier(tab)
        if let p = tabProxies[key] { return p }
        let p = ExtTab(tab: tab, bridge: self)
        tabProxies[key] = p
        return p
    }

    // MARK: delegate

    func webExtensionController(_ controller: WKWebExtensionController,
                               openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [extWindow]
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                               focusedWindowFor context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        extWindow
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                               openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                               for context: WKWebExtensionContext,
                               completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let host else { completionHandler(nil, nil); return }
        let tab = host.extOpenTab(url: configuration.url)
        completionHandler(proxy(for: tab), nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                               presentActionPopup action: WKWebExtension.Action,
                               for context: WKWebExtensionContext,
                               completionHandler: @escaping ((any Error)?) -> Void) {
        if let popover = action.popupPopover {
            host?.extPresentActionPopover(popover, for: context)
            // Some popups (async/React-rendered) size themselves to the viewport, which WebKit
            // initially reports as ~1×1, so they collapse to blank. If that happened, force a
            // default document size so WebKit re-measures and the popup renders.
            if let pv = action.popupWebView {
                pv.evaluateJavaScript("innerWidth") { r, _ in
                    guard let w = r as? Int, w <= 1 else { return }
                    let force = "(function(){var s=document.createElement('style');s.textContent='html,body{width:380px!important;min-width:380px!important;height:600px!important;min-height:600px!important}';document.head.appendChild(s);})();true"
                    pv.evaluateJavaScript(force, completionHandler: nil)
                }
            }
        }
        completionHandler(nil)
    }

    // MARK: notify (keep extensions in sync as Muninn's tabs change)

    func didOpen(_ tab: BrowserTab) {
        ExtensionManager.shared.controller.didOpenTab(proxy(for: tab))
    }
    func didClose(_ tab: BrowserTab) {
        let p = proxy(for: tab)
        ExtensionManager.shared.controller.didCloseTab(p, windowIsClosing: false)
        tabProxies[ObjectIdentifier(tab)] = nil
    }
    func didActivate(_ tab: BrowserTab, previous: BrowserTab?) {
        ExtensionManager.shared.controller.didActivateTab(proxy(for: tab),
                                                          previousActiveTab: previous.map { proxy(for: $0) })
    }
}

/// A `WKWebExtensionTab` backed by one Muninn `BrowserTab`.
@MainActor
final class ExtTab: NSObject, WKWebExtensionTab {
    weak var tab: BrowserTab?
    weak var bridge: ExtensionBridge?

    init(tab: BrowserTab, bridge: ExtensionBridge) { self.tab = tab; self.bridge = bridge }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { tab?.webView }
    func url(for context: WKWebExtensionContext) -> URL? { tab?.webView.url }
    func title(for context: WKWebExtensionContext) -> String? { tab?.title }
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { bridge?.extWindow }
    func isSelected(for context: WKWebExtensionContext) -> Bool { bridge?.host?.extActiveTab() === tab }
    func isPinned(for context: WKWebExtensionContext) -> Bool {
        let k = tab?.kind; return k == .pinned || k == .favourite
    }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(tab?.webView.isLoading ?? false) }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let t = tab { bridge?.host?.extActivate(t) }
        completionHandler(nil)
    }
    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let t = tab { bridge?.host?.extCloseTab(t) }
        completionHandler(nil)
    }
    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        tab?.webView.load(URLRequest(url: url))
        completionHandler(nil)
    }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { tab?.webView.reloadFromOrigin() } else { tab?.webView.reload() }
        completionHandler(nil)
    }
    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        tab?.webView.goBack(); completionHandler(nil)
    }
    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        tab?.webView.goForward(); completionHandler(nil)
    }
}

/// The single `WKWebExtensionWindow` representing Muninn's main window.
@MainActor
final class ExtWindow: NSObject, WKWebExtensionWindow {
    weak var bridge: ExtensionBridge?

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let bridge, let host = bridge.host else { return [] }
        return host.extLiveTabs().map { bridge.proxy(for: $0) }
    }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let bridge, let t = bridge.host?.extActiveTab() else { return nil }
        return bridge.proxy(for: t)
    }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func frame(for context: WKWebExtensionContext) -> CGRect { bridge?.host?.extNSWindow.frame ?? .zero }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        bridge?.host?.extNSWindow.screen?.frame ?? .zero
    }
    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        bridge?.host?.extNSWindow.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
}
