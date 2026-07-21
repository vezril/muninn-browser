import AppKit
import WebKit

/// "Little Muninn" — a compact, ephemeral window for a quick lookup / instant triage.
/// It carries the same Pass shim (shared background host via the passed broker). Glance,
/// then either dismiss it (Esc / close) or promote the page into the main window as a tab
/// ("Open in Muninn").
@MainActor
final class QuickLookWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let injector: InjectionCoordinator
    private var webView: WKWebView { injector.webView }

    private let addressField = NSTextField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()

    /// "Open in Muninn" — hand the current URL to the host to open as a tab.
    var onPromote: ((URL) -> Void)?
    /// Fired when the window closes (host drops its reference).
    var onClosed: ((QuickLookWindow) -> Void)?

    private var titleObs: NSKeyValueObservation?
    private var urlObs: NSKeyValueObservation?
    private var keyMonitor: Any?

    init(broker: MessageBroker, id: Int) {
        injector = InjectionCoordinator(broker: broker, contextName: "quicklook-\(id)")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        buildUI()
        titleObs = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.refreshAddress(wv) }
        }
        urlObs = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.refreshAddress(wv) }
        }
    }

    private func buildUI() {
        configure(backButton, symbol: "chevron.backward", action: #selector(goBack))
        configure(forwardButton, symbol: "chevron.forward", action: #selector(goForward))
        backButton.isEnabled = false; forwardButton.isEnabled = false

        addressField.placeholderString = "Search or Enter URL…"
        addressField.font = .systemFont(ofSize: 12)
        addressField.bezelStyle = .roundedBezel
        addressField.target = self
        addressField.action = #selector(addressSubmitted)
        addressField.translatesAutoresizingMaskIntoConstraints = false

        let promote = NSButton(title: " Open in Muninn",
                               image: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "Open in Muninn")!,
                               target: self, action: #selector(promote))
        promote.imagePosition = .imageLeading
        promote.bezelStyle = .rounded
        promote.controlSize = .small
        promote.font = .systemFont(ofSize: 11, weight: .medium)
        promote.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSStackView(views: [backButton, forwardButton, addressField, promote])
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setHuggingPriority(.defaultLow, for: .horizontal)

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let web = webView
        web.translatesAutoresizingMaskIntoConstraints = false
        web.wantsLayer = true
        web.layer?.cornerRadius = 8
        web.layer?.masksToBounds = true
        content.addSubview(bar); content.addSubview(web)
        window.contentView = content

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 78), // clear traffic lights
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            bar.heightAnchor.constraint(equalToConstant: 26),
            web.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            web.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    private func configure(_ b: NSButton, symbol: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        b.isBordered = false
        b.contentTintColor = .labelColor
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 24).isActive = true
    }

    func present() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Esc / Cmd+W close this window while it's key.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.window.isKeyWindow else { return e }
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.keyCode == 53 { self.window.performClose(nil); return nil }              // Esc
            if flags == .command, e.charactersIgnoringModifiers?.lowercased() == "w" {     // Cmd+W
                self.window.performClose(nil); return nil
            }
            return e
        }
    }

    func load(_ url: URL) { injector.load(url); addressField.stringValue = url.absoluteString }
    func focusAddress() { window.makeFirstResponder(addressField) }

    private func refreshAddress(_ wv: WKWebView) {
        if window.firstResponder != addressField.currentEditor(), let u = wv.url {
            addressField.stringValue = u.absoluteString
        }
        backButton.isEnabled = wv.canGoBack
        forwardButton.isEnabled = wv.canGoForward
        window.title = wv.title ?? ""
    }

    @objc private func addressSubmitted() {
        var s = addressField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        let looksURL = !s.contains(" ") && (s.contains("://") || (s.contains(".") && !s.contains(" ")))
        if looksURL {
            if !s.contains("://") { s = "https://" + s }
            if let u = URL(string: s) { injector.load(u) }
        } else {
            var c = URLComponents(string: "https://duckduckgo.com/")!
            c.queryItems = [URLQueryItem(name: "q", value: s)]
            if let u = c.url { injector.load(u) }
        }
    }

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func promote() {
        guard let url = webView.url else { return }
        onPromote?(url)
        window.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        titleObs = nil; urlObs = nil
        injector.stop()
        onClosed?(self)
    }
}
