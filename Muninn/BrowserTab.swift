import AppKit
import WebKit

/// A tab-bar chip view that remembers which tab index it represents (for the
/// click-to-select gesture).
final class TabChipView: NSView {
    var index: Int = 0
}

/// One browser tab: an injected `WKWebView` (the Pass content shim rides along, per-tab
/// broker context) plus its title/url tracking for the tab bar and address field.
@MainActor
final class BrowserTab {
    let id: Int
    let injector: InjectionCoordinator
    var webView: WKWebView { injector.webView }

    /// Display title (page title, falling back to host / "New Tab").
    private(set) var title: String = "New Tab"
    /// Fired when the tab's title or url changes (so the shell can refresh the UI).
    var onChange: (() -> Void)?

    private var titleObs: NSKeyValueObservation?
    private var urlObs: NSKeyValueObservation?

    init(id: Int, broker: MessageBroker) {
        self.id = id
        self.injector = InjectionCoordinator(broker: broker, contextName: "page-\(id)")
        titleObs = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.refreshTitle(wv); self?.onChange?() }
        }
        urlObs = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.refreshTitle(wv); self?.onChange?() }
        }
    }

    private func refreshTitle(_ wv: WKWebView) {
        if let t = wv.title, !t.isEmpty { title = t }
        else if let h = wv.url?.host { title = h }
        else { title = "New Tab" }
    }

    func load(_ url: URL) { injector.load(url) }

    func stop() {
        titleObs = nil; urlObs = nil
        injector.stop()
    }
}
