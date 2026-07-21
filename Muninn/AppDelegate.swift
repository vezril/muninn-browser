import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: AppShell?
    private let aboutPanel = AboutPanelController()
    /// External links that arrived before the shell was ready.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under XCTest the app is only a host for WKWebView; show no window
        // (keeps `xcodebuild test` headless — ground rule 2).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            NSApp.setActivationPolicy(.prohibited)
            return
        }

        if ShimDiagnostic.isEnabled {
            ShimDiagnostic.run() // headless S1 boot; no window
            return
        }

        NSApp.setActivationPolicy(.regular)
        buildMenu()

        let shell = AppShell()
        self.shell = shell
        shell.present()
        // Flush any links that arrived during launch (opened via an external link).
        for url in pendingURLs { shell.openQuickLook(url) }
        pendingURLs.removeAll()
    }

    /// External links (Muninn as default browser) open in a Quick Look window.
    func application(_ application: NSApplication, open urls: [URL]) {
        let web = urls.filter { $0.scheme == "http" || $0.scheme == "https" }
        guard !web.isEmpty else { return }
        if let shell { web.forEach { shell.openQuickLook($0) } }
        else { pendingURLs.append(contentsOf: web) }
    }

    /// Warn-before-quitting (General setting).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppSettings.warnBeforeQuitting else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Muninn?"
        alert.informativeText = "Your open tabs in this session will be closed."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    @objc private func openSettings() { shell?.openSettings() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func newQuickLook() { shell?.openQuickLook(nil) }

    @objc private func setAsDefaultBrowser() {
        let bundleURL = Bundle.main.bundleURL
        let ws = NSWorkspace.shared
        ws.setDefaultApplication(at: bundleURL, toOpenURLsWithScheme: "https") { _ in }
        ws.setDefaultApplication(at: bundleURL, toOpenURLsWithScheme: "http") { error in
            Task { @MainActor in
                let alert = NSAlert()
                if let error {
                    alert.messageText = "Couldn't set Muninn as the default browser"
                    alert.informativeText = "\(error.localizedDescription)\n\nYou can set it manually in System Settings › Desktop & Dock › Default web browser."
                } else {
                    alert.messageText = "Muninn is now your default browser"
                    alert.informativeText = "Links from other apps will open in a Quick Look window."
                }
                alert.runModal()
            }
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Muninn",
            action: #selector(showAbout),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "Set as Default Browser…", action: #selector(setAsDefaultBrowser), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Muninn",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu — Quick Look (Little Muninn).
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        // (no key equivalent — the remappable shortcut is handled by AppShell's key monitor)
        fileMenu.addItem(withTitle: "New Quick Look", action: #selector(newQuickLook), keyEquivalent: "").target = self
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu — routes the standard editing shortcuts (Cmd A/C/V/X/Z) through the
        // responder chain to text fields and the web view.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        aboutPanel.show()
    }
}
