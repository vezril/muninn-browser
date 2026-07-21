import AppKit
import WebKit

/// Arc-style **Peek**: clicking a cross-site link in a pinned/favourite tab opens the link in
/// this preview overlay instead of navigating the anchored tab away from its home. Dismiss it
/// (Esc / close / click the dimmed area) or **Open in Tab** to promote it to a real tab.
@MainActor
final class PeekOverlay: NSView {
    private let injector: InjectionCoordinator
    private var webView: WKWebView { injector.webView }

    var onPromote: ((URL) -> Void)?
    var onClose: (() -> Void)?

    private let card = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let favicon = NSImageView()
    private var titleObs: NSKeyValueObservation?
    private var urlObs: NSKeyValueObservation?
    private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    init(broker: MessageBroker, id: Int) {
        injector = InjectionCoordinator(broker: broker, contextName: "peek-\(id)")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor // dims the anchored tab
        buildCard()
        titleObs = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.titleLabel.stringValue = wv.title?.isEmpty == false ? wv.title! : (wv.url?.host ?? "") }
        }
        urlObs = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated { if self?.titleLabel.stringValue.isEmpty == true { self?.titleLabel.stringValue = wv.url?.host ?? "" } }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    // Clicking the dimmed area (outside the card) closes.
    override func mouseDown(with event: NSEvent) {
        if !card.frame.contains(convert(event.locationInWindow, from: nil)) { onClose?() }
    }

    private func buildCard() {
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        card.layer?.masksToBounds = false
        card.shadow = NSShadow()
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.3
        card.layer?.shadowRadius = 24
        card.layer?.shadowOffset = CGSize(width: 0, height: -6)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])

        favicon.imageScaling = .scaleProportionallyDown
        favicon.wantsLayer = true; favicon.layer?.cornerRadius = 3; favicon.layer?.masksToBounds = true
        favicon.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        favicon.contentTintColor = .secondaryLabelColor
        favicon.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let open = NSButton(title: " Open in Tab",
                            image: NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Open in Tab")!,
                            target: self, action: #selector(promote))
        open.imagePosition = .imageLeading
        open.bezelStyle = .rounded
        open.controlSize = .small
        open.font = .systemFont(ofSize: 11, weight: .medium)
        open.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))!,
                             target: self, action: #selector(dismiss))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        let web = webView
        web.translatesAutoresizingMaskIntoConstraints = false
        web.wantsLayer = true; web.layer?.cornerRadius = 10; web.layer?.masksToBounds = true
        card.addSubview(bar); card.addSubview(web)
        bar.addSubview(favicon); bar.addSubview(titleLabel); bar.addSubview(open); bar.addSubview(close)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: card.topAnchor),
            bar.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 40),
            favicon.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            favicon.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            favicon.widthAnchor.constraint(equalToConstant: 16),
            favicon.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            open.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
            open.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            open.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            close.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 20),
            web.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2),
            web.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            web.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            web.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
    }

    func activate(in parent: NSView, url: URL) {
        frame = parent.bounds
        autoresizingMask = [.width, .height]
        parent.addSubview(self)
        injector.load(url)
        window?.makeFirstResponder(self)
        // Slide the card in from the right + fade the scrim.
        alphaValue = 0
        card.layer?.setAffineTransform(CGAffineTransform(translationX: 40, y: 0))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            animator().alphaValue = 1
            card.layer?.setAffineTransform(.identity)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.onClose?(); return nil } // Esc
            return e
        }
    }

    @objc private func promote() {
        if let url = webView.url { onPromote?(url) }
        onClose?()
    }
    @objc private func dismiss() { onClose?() }

    func tearDown() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        titleObs = nil; urlObs = nil
        injector.stop()
    }
}
