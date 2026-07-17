import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: AppShell?
    private let aboutPanel = AboutPanelController()

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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
        appMenu.addItem(
            withTitle: "Quit Muninn",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        aboutPanel.show()
    }
}
