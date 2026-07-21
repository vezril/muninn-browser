import AppKit
import WebKit

/// Transparent catcher over the video: a click toggles playback.
private final class CatcherView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true } // toggle even when not key
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Arc-style **Mini Player**: a small always-on-top window that hosts a tab's live web view so
/// media keeps playing while you browse elsewhere. It shows just the video (the host reparents
/// the `<video>` into a clean fullscreen wrapper), with play/pause, return-to-tab, and close.
/// A titled-but-chromeless window gives native edge-resize and title-bar dragging.
@MainActor
final class MiniPlayerWindow: NSObject {
    let window: NSWindow
    private let container = NSView()
    private let controlBar = NSView()
    private let playPauseButton = NSButton()
    private let clickCatcher = CatcherView()
    private var playing = true

    var onReturn: (() -> Void)?
    var onClose: (() -> Void)?
    var onTogglePlay: (() -> Void)?

    override init() {
        // NOT .fullSizeContentView — the title bar stays a clear drag strip and the web view
        // doesn't cover the resize edges, so native drag + edge-resize both work.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.level = .floating
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.minSize = NSSize(width: 260, height: 200)
        // Chromeless: no traffic lights — the control bar has our own close.
        for b: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(b)?.isHidden = true
        }
        super.init()
        buildUI()
    }

    private func buildUI() {
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = container

        controlBar.wantsLayer = true
        controlBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        controlBar.translatesAutoresizingMaskIntoConstraints = false

        func button(_ symbol: String, _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))!,
                             target: self, action: action)
            b.isBordered = false; b.contentTintColor = .white
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 26).isActive = true
            return b
        }
        playPauseButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        playPauseButton.isBordered = false; playPauseButton.contentTintColor = .white
        playPauseButton.target = self; playPauseButton.action = #selector(togglePlay(_:))
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.widthAnchor.constraint(equalToConstant: 26).isActive = true

        let returnBtn = button("arrow.up.left.square", #selector(returnToTab(_:))); returnBtn.toolTip = "Return to tab"
        let closeBtn = button("xmark", #selector(closeSelf(_:))); closeBtn.toolTip = "Close"

        container.addSubview(controlBar)
        controlBar.addSubview(playPauseButton); controlBar.addSubview(returnBtn); controlBar.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            controlBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controlBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: 34),
            playPauseButton.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: 12),
            playPauseButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -12),
            closeBtn.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            returnBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -12),
            returnBtn.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
        ])
    }

    /// Borrow the tab's web view (media keeps playing) above the control bar, with a
    /// click-to-toggle catcher and an icon-flash overlay on top of it.
    func attach(_ web: WKWebView) {
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web, positioned: .below, relativeTo: controlBar)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: controlBar.topAnchor),
        ])

        clickCatcher.onClick = { [weak self] in self?.doToggle() }
        clickCatcher.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(clickCatcher, positioned: .below, relativeTo: controlBar)
        NSLayoutConstraint.activate([
            clickCatcher.topAnchor.constraint(equalTo: web.topAnchor),
            clickCatcher.leadingAnchor.constraint(equalTo: web.leadingAnchor),
            clickCatcher.trailingAnchor.constraint(equalTo: web.trailingAnchor),
            clickCatcher.bottomAnchor.constraint(equalTo: web.bottomAnchor),
        ])
    }

    // The icon flash is rendered in the web view (via `onTogglePlay` → `__muninnToggle`),
    // because an AppKit overlay doesn't composite reliably above WKWebView content.
    private func doToggle() { onTogglePlay?() }

    func present() {
        if let f = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: f.maxX - window.frame.width - 24, y: f.minY + 24))
        }
        window.makeKeyAndOrderFront(nil)
    }

    func setPlaying(_ playing: Bool) {
        self.playing = playing
        playPauseButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    }

    /// Release the borrowed web view and hide the window.
    func teardown() {
        container.subviews.compactMap { $0 as? WKWebView }.forEach { $0.removeFromSuperview() }
        window.orderOut(nil)
    }

    @objc private func togglePlay(_ sender: NSButton) { press(sender); doToggle() }
    @objc private func returnToTab(_ sender: NSButton) { press(sender); onReturn?() }
    @objc private func closeSelf(_ sender: NSButton) { press(sender); onClose?() }

    /// A quick press flash + haptic tap on a control button.
    private func press(_ button: NSButton) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        button.alphaValue = 0.35
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.animator().alphaValue = 1
        }
    }
}
