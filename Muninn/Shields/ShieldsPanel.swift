import AppKit

/// The per-site Shields popover: a master Shields toggle, a per-site "block scripts" toggle, and
/// a status readout of which protections are active. Global protection on/off lives in Settings.
@MainActor
final class ShieldsPanelController: NSViewController {
    var host: String?
    var onToggled: (() -> Void)?       // host reloads the tab so changes apply
    var onOpenSettings: (() -> Void)?

    private let shields = ShieldsManager.shared

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 288, height: 10))
        root.translatesAutoresizingMaskIntoConstraints = false

        let up = shields.shieldsUp(for: host)
        let siteLabel = shields.siteKey(host) ?? "this page"

        let title = NSTextField(labelWithString: "Shields")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let site = NSTextField(labelWithString: siteLabel)
        site.font = .systemFont(ofSize: 12); site.textColor = .secondaryLabelColor
        site.lineBreakMode = .byTruncatingTail

        let master = NSSwitch(); master.state = up ? .on : .off
        master.target = self; master.action = #selector(toggleShields(_:))
        let masterRow = row("Shields for this site", master)

        // Active-protection status (read-only; reflects global settings, dimmed when Shields down).
        let ads = statusRow("Block ads & trackers", active: up && shields.blockAds)
        let https = statusRow("Upgrade connections to HTTPS", active: up && shields.upgradeHTTPS)
        let cookies = statusRow("Block cross-site cookies", active: up && shields.blockCookies)
        let strip = statusRow("Strip tracking parameters", active: up && shields.stripQueryParams)
        let bounce = statusRow("Bounce-tracking protection", active: up && shields.debounce)
        let fp = statusRow("Fingerprinting protection", active: up && shields.fingerprintProtection)
        let cookieNotices = statusRow("Cookie-consent notices blocked", active: up && shields.blockCookieNotices)

        let scripts = NSSwitch(); scripts.state = shields.scriptsBlocked(for: host) ? .on : .off
        scripts.isEnabled = up
        scripts.target = self; scripts.action = #selector(toggleScripts(_:))
        let scriptsRow = row("Block scripts on this site", scripts)

        let sep = NSBox(); sep.boxType = .separator
        let settings = NSButton(title: "Shields Settings…", target: self, action: #selector(openSettings))
        settings.bezelStyle = .inline; settings.isBordered = false
        settings.contentTintColor = .controlAccentColor
        settings.font = .systemFont(ofSize: 12)

        let head = NSStackView(views: [title, site]); head.orientation = .vertical; head.alignment = .leading; head.spacing = 1
        let stack = NSStackView(views: [head, masterRow, sep, ads, https, cookies, strip, bounce, fp, cookieNotices, scriptsRow, settings])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(14, after: head)
        stack.setCustomSpacing(12, after: masterRow)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            sep.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        for r in [masterRow, scriptsRow, ads, https, cookies, strip, bounce, fp, cookieNotices] {
            r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        view = root
    }

    private func row(_ label: String, _ control: NSView) -> NSView {
        let l = NSTextField(labelWithString: label); l.font = .systemFont(ofSize: 13)
        l.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        let r = NSView()
        r.addSubview(l); r.addSubview(control)
        NSLayoutConstraint.activate([
            r.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            l.leadingAnchor.constraint(equalTo: r.leadingAnchor),
            l.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: r.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: l.trailingAnchor, constant: 12),
        ])
        return r
    }

    private func statusRow(_ label: String, active: Bool) -> NSView {
        let symbol = active ? "checkmark.circle.fill" : "minus.circle"
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = active ? .systemGreen : .tertiaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 12); l.textColor = active ? .labelColor : .tertiaryLabelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        let r = NSView()
        r.addSubview(icon); r.addSubview(l)
        NSLayoutConstraint.activate([
            r.heightAnchor.constraint(equalToConstant: 20),
            icon.leadingAnchor.constraint(equalTo: r.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            l.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            l.centerYAnchor.constraint(equalTo: r.centerYAnchor),
        ])
        return r
    }

    @objc private func toggleShields(_ s: NSSwitch) {
        shields.setShieldsUp(s.state == .on, for: host)
        reloadPanel(); onToggled?()
    }
    @objc private func toggleScripts(_ s: NSSwitch) {
        shields.setScriptsBlocked(s.state == .on, for: host)
        onToggled?()
    }
    @objc private func openSettings() { dismiss(nil); onOpenSettings?() }

    /// Rebuild the popover contents after the master toggle (enables/disables the rest).
    private func reloadPanel() { loadView() }
}
