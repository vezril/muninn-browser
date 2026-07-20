import AppKit
import WebKit

/// The minimal navigable shell (FR-1/4/5): one window, one tab (the page
/// `WKWebView` from `InjectionCoordinator`, which carries the isolated-world shim
/// + fork.js scoping), an address field, and back/forward/reload. Owns the
/// broker, the always-resident background host, and the page context — so the
/// auth-fork bus (page ⇄ broker ⇄ host) is live end to end.
///
/// Not the FR-2/3 multi-tab model (E9); one tab.
@MainActor
final class AppShell: NSObject {
    private let window: NSWindow
    let broker: MessageBroker
    let host: BackgroundHost
    let page: InjectionCoordinator
    private var popup: PopupHost?

    private let addressField = NSTextField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private var urlObservation: NSKeyValueObservation?

    override init() {
        broker = MessageBroker()
        host = BackgroundHost(broker: broker)
        page = InjectionCoordinator(broker: broker)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()

        // The auth-fork is background-driven: background.js opens the fork URL via
        // tabs.create/windows.create. Route those to the shell's one tab.
        var didOpen = false
        broker.onOpenURL = { [weak self] url, _ in didOpen = true; self?.page.load(url) }

        // E6 human-gate observation: payload-free signals written to a FLUSHED
        // file (stdout is block-buffered in a windowed app and won't appear until
        // exit). Never logs message content (ground rule 1).
        if ProcessInfo.processInfo.environment["MUNINN_E6_GATE"] != nil {
            let logPath = ProcessInfo.processInfo.environment["MUNINN_E6_GATE_LOG"]
            func gate(_ line: String) {
                let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
                if let p = logPath {
                    if !FileManager.default.fileExists(atPath: p) { FileManager.default.createFile(atPath: p, contents: nil) }
                    if let fh = FileHandle(forWritingAtPath: p) {
                        fh.seekToEndOfFile(); fh.write(Data(stamped.utf8)); try? fh.close()
                    }
                }
                FileHandle.standardError.write(Data(stamped.utf8)) // stderr is unbuffered
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
                    // Ground rule 1: surface ONLY specific, non-sensitive fork/permission
                    // diagnostic markers (never tokens/session) — log just the matched marker.
                    let markers = ["Invalid fork state", "missing permissions", "consumeFork",
                                   "fork state", "InactiveSession", "pullFork"]
                    if let hit = markers.first(where: { text.localizedCaseInsensitiveContains($0) }) {
                        gate("E6-GATE bg-marker: \(hit)")
                    }
                }
            }
        }

        host.start() // background.js resident; may open the fork URL immediately
        buildUI()

        // Fallback: if background.js hasn't driven navigation shortly after boot,
        // land on the account page so the window isn't blank.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if !didOpen { self?.navigate(to: "https://account.proton.me") }
        }
        window.title = "Muninn"
        window.center()
    }

    func present() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Sign-in paths (gate-controlled). MUNINN_FORKINIT: the minimal fork-init shim
        // (retire Risk 1 without the full popup UI). MUNINN_POPUP: the real popup.
        if ProcessInfo.processInfo.environment["MUNINN_FORKINIT"] != nil { forkInit() }
        else if ProcessInfo.processInfo.environment["MUNINN_POPUP"] != nil { openPopup() }
        else { navigate(to: "https://account.proton.me") }
    }

    /// Minimal auth-fork initiation (what Proton's `popup.js` "Sign in" does, hand-rolled):
    /// generate a random `state` nonce, store the fork `localState` under
    /// `storage.session["f"+state]` (the SAME `ExtensionStorage` background.js reads on
    /// consume), and navigate to the `/authorize` fork endpoint. The account login then
    /// forks and messages the extension; consume finds `f<state>` → `pullFork` (via the
    /// native fetch proxy). No crypto key in the URL — the state is a plain nonce and the
    /// key/keyPassword come from the account app's fork message.
    func forkInit() {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let nonce = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        // Value is the JSON STRING background parses back (JSON.parse(localState)); "{}" ⇒
        // a non-null localState, which is all the "Invalid fork state" check requires.
        broker.storage.set(.session, ["f\(nonce)": "{}"])
        let url = "https://account.proton.me/authorize?app=proton-pass-extension"
            + "&state=\(nonce)&independent=0&prompt=login&promptBypass=sso&promptType=offline&pt=offline&t=3"
        navigate(to: url)
    }

    /// Open the Pass popup (renders Proton's popup.html/popup.js); its "Sign in" runs the
    /// real fork-initiation. The fork URL it opens is routed to the shell tab via
    /// `broker.onOpenURL` (already wired in init).
    func openPopup() {
        let p = PopupHost(broker: broker)
        self.popup = p
        p.load()
        p.present()
    }

    // MARK: - UI

    private func buildUI() {
        let web = page.webView!
        web.translatesAutoresizingMaskIntoConstraints = false

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

        let content = NSView()
        content.addSubview(toolbar)
        content.addSubview(web)
        window.contentView = content

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Reflect the committed URL in the address field (no logging of content).
        urlObservation = web.observe(\.url, options: [.new]) { [weak self] wv, _ in
            MainActor.assumeIsolated {
                self?.addressField.stringValue = wv.url?.absoluteString ?? ""
                self?.backButton.isEnabled = wv.canGoBack
                self?.forwardButton.isEnabled = wv.canGoForward
            }
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

    // MARK: - actions

    private func navigate(to string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return }
        page.load(url)
    }

    @objc private func addressSubmitted() { navigate(to: addressField.stringValue) }
    @objc private func goBack() { page.webView.goBack() }
    @objc private func goForward() { page.webView.goForward() }
    @objc private func reload() { page.webView.reload() }
}
