import AppKit

/// The Settings window: a top toolbar (General / Profiles / Shortcuts / Advanced, each with an
/// icon) and a content pane. Reads and writes preferences through the host `AppShell`.
@MainActor
final class SettingsWindowController: NSWindowController {
    private weak var host: AppShell?

    private let content = NSView()
    private var navButtons: [NSButton] = []
    private let sections: [(title: String, icon: String)] = [
        ("General", "gearshape"), ("Profiles", "person.2"), ("Routing", "arrow.triangle.branch"),
        ("Shortcuts", "keyboard"), ("Advanced", "slider.horizontal.3"),
    ]
    private let routingList = NSStackView()

    // Profiles state
    private var selectedProfileId: UUID?
    private let profileBar = NSStackView()
    private let profileForm = NSView()

    init(host: AppShell) {
        self.host = host
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                           styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        super.init(window: win)
        buildChrome()
        select(0)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: chrome

    private func buildChrome() {
        let root = NSView()
        window?.contentView = root

        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false

        let navStack = NSStackView()
        navStack.orientation = .horizontal
        navStack.spacing = 6
        navStack.translatesAutoresizingMaskIntoConstraints = false
        for (i, s) in sections.enumerated() {
            let b = NSButton(title: s.title,
                             image: NSImage(systemSymbolName: s.icon, accessibilityDescription: nil)!
                                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))!,
                             target: self, action: #selector(navClicked(_:)))
            b.tag = i
            b.imagePosition = .imageAbove
            b.isBordered = false
            b.font = .systemFont(ofSize: 11, weight: .medium)
            b.contentTintColor = .labelColor
            b.wantsLayer = true
            b.layer?.cornerRadius = 7
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 74).isActive = true
            b.heightAnchor.constraint(equalToConstant: 52).isActive = true
            navButtons.append(b)
            navStack.addArrangedSubview(b)
        }
        bar.addSubview(navStack)

        let sep = NSBox(); sep.boxType = .separator; sep.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar); root.addSubview(sep); root.addSubview(content)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 66),
            navStack.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            navStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            sep.topAnchor.constraint(equalTo: bar.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: sep.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    @objc private func navClicked(_ sender: NSButton) { select(sender.tag) }

    private func select(_ index: Int) {
        for (i, b) in navButtons.enumerated() {
            b.layer?.backgroundColor = (i == index ? NSColor.controlAccentColor.withAlphaComponent(0.20) : .clear).cgColor
            b.contentTintColor = i == index ? .controlAccentColor : .labelColor
        }
        content.subviews.forEach { $0.removeFromSuperview() }
        let view: NSView = [generalView, profilesView, routingView, shortcutsView, advancedView][index]()
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: shared UI helpers

    private func heading(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text); l.font = .systemFont(ofSize: 17, weight: .bold); return l
    }
    private func makeSwitch(_ on: Bool, _ action: Selector) -> NSSwitch {
        let sw = NSSwitch(); sw.state = on ? .on : .off; sw.target = self; sw.action = action; return sw
    }
    /// A settings row: description on the left, control on the right.
    private func row(_ label: String, _ control: NSView) -> NSView {
        let r = NSView()
        let l = NSTextField(labelWithString: label); l.font = .systemFont(ofSize: 13)
        l.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        r.addSubview(l); r.addSubview(control)
        NSLayoutConstraint.activate([
            r.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            l.leadingAnchor.constraint(equalTo: r.leadingAnchor),
            l.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: r.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: l.trailingAnchor, constant: 16),
        ])
        return r
    }
    /// A vertical stack whose rows fill its width (pin the stack's leading AND trailing).
    private func formStack(_ rows: [NSView]) -> NSStackView {
        let s = NSStackView(views: rows)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 12
        s.translatesAutoresizingMaskIntoConstraints = false
        for r in rows { r.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = true }
        return s
    }

    // MARK: General

    private func generalView() -> NSView {
        let v = NSView()
        let title = heading("General")
        let stack = formStack([ row("Warn before quitting", makeSwitch(host?.settingsWarnBeforeQuitting ?? false, #selector(toggleWarnQuit(_:)))) ])
        title.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(title); v.addSubview(stack)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -24),
        ])
        return v
    }
    @objc private func toggleWarnQuit(_ s: NSSwitch) { host?.settingsWarnBeforeQuitting = (s.state == .on) }

    // MARK: Profiles (list on top, settings below)

    private func profilesView() -> NSView {
        let v = NSView()
        let title = heading("Profiles")
        title.translatesAutoresizingMaskIntoConstraints = false

        // Left pane: profile list (names top → bottom) with +/−/✎ at the bottom.
        let listContainer = NSView()
        listContainer.wantsLayer = true
        listContainer.layer?.borderWidth = 1
        listContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        listContainer.layer?.cornerRadius = 8
        listContainer.translatesAutoresizingMaskIntoConstraints = false

        profileBar.orientation = .vertical
        profileBar.alignment = .leading
        profileBar.spacing = 1
        profileBar.translatesAutoresizingMaskIntoConstraints = false

        let add = actionButton("plus", #selector(addProfile))
        let rem = actionButton("minus", #selector(removeProfile))
        let edit = actionButton("pencil", #selector(renameProfile))
        let controls = NSStackView(views: [add, rem, edit])
        controls.orientation = .horizontal; controls.spacing = 0
        controls.translatesAutoresizingMaskIntoConstraints = false

        listContainer.addSubview(profileBar); listContainer.addSubview(controls)
        profileForm.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(title); v.addSubview(listContainer); v.addSubview(profileForm)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            listContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            listContainer.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            listContainer.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -24),
            listContainer.widthAnchor.constraint(equalToConstant: 200),
            // Profiles listed from the TOP.
            profileBar.topAnchor.constraint(equalTo: listContainer.topAnchor, constant: 4),
            profileBar.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            profileBar.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            profileBar.bottomAnchor.constraint(lessThanOrEqualTo: controls.topAnchor),
            controls.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            controls.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            controls.heightAnchor.constraint(equalToConstant: 26),
            profileForm.topAnchor.constraint(equalTo: listContainer.topAnchor),
            profileForm.leadingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: 24),
            profileForm.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -24),
            profileForm.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -24),
        ])

        if selectedProfileId == nil { selectedProfileId = host?.settingsProfiles().first?.id }
        rebuildProfileBar(); rebuildProfileForm()
        return v
    }

    private func actionButton(_ symbol: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))!,
                         target: self, action: action)
        b.isBordered = false
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    private func rebuildProfileBar() {
        profileBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let host else { return }
        for p in host.settingsProfiles() {
            let row = ProfileRow()
            row.onClick = { [weak self] in self?.selectedProfileId = p.id; self?.rebuildProfileBar(); self?.rebuildProfileForm() }
            row.wantsLayer = true
            let selected = p.id == selectedProfileId
            row.layer?.backgroundColor = (selected ? NSColor.controlAccentColor.withAlphaComponent(0.18) : .clear).cgColor
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 198).isActive = true
            row.heightAnchor.constraint(equalToConstant: 30).isActive = true
            let name = NSTextField(labelWithString: p.name)
            name.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
            name.textColor = selected ? .controlAccentColor : .labelColor
            name.lineBreakMode = .byTruncatingTail
            let count = host.settingsWorkspaceCount(for: p.id)
            let badge = NSTextField(labelWithString: "\(count) space\(count == 1 ? "" : "s")")
            badge.font = .systemFont(ofSize: 11); badge.textColor = .secondaryLabelColor
            name.translatesAutoresizingMaskIntoConstraints = false
            badge.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(name); row.addSubview(badge)
            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
                name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                badge.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
                badge.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                name.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6),
            ])
            profileBar.addArrangedSubview(row)
        }
    }

    private func rebuildProfileForm() {
        profileForm.subviews.forEach { $0.removeFromSuperview() }
        guard let host, let pid = selectedProfileId, let p = host.settingsProfiles().first(where: { $0.id == pid }) else { return }

        let engine = NSPopUpButton()
        engine.addItems(withTitles: SearchEngine.allCases.map { $0.displayName })
        engine.selectItem(at: SearchEngine.allCases.firstIndex(of: p.searchEngine) ?? 0)
        engine.target = self; engine.action = #selector(engineChanged(_:))

        let archive = NSPopUpButton()
        archive.addItems(withTitles: AutoArchive.allCases.map { $0.displayName })
        archive.selectItem(at: AutoArchive.allCases.firstIndex(of: p.autoArchive) ?? 0)
        archive.target = self; archive.action = #selector(archiveChanged(_:))

        let dlPath = NSTextField(labelWithString: p.downloadFolder.path)
        dlPath.font = .systemFont(ofSize: 11); dlPath.textColor = .secondaryLabelColor
        dlPath.lineBreakMode = .byTruncatingMiddle
        let dlBtn = NSButton(title: "Choose…", target: self, action: #selector(chooseDownloadFolder))
        dlBtn.bezelStyle = .rounded; dlBtn.controlSize = .small; dlBtn.translatesAutoresizingMaskIntoConstraints = false
        dlPath.translatesAutoresizingMaskIntoConstraints = false
        let dl = NSView()
        dl.addSubview(dlPath); dl.addSubview(dlBtn)
        NSLayoutConstraint.activate([
            dl.heightAnchor.constraint(equalToConstant: 22),
            dlBtn.trailingAnchor.constraint(equalTo: dl.trailingAnchor),
            dlBtn.centerYAnchor.constraint(equalTo: dl.centerYAnchor),
            dlPath.leadingAnchor.constraint(equalTo: dl.leadingAnchor),
            dlPath.trailingAnchor.constraint(equalTo: dlBtn.leadingAnchor, constant: -10),
            dlPath.centerYAnchor.constraint(equalTo: dl.centerYAnchor),
        ])

        let stack = formStack([
            row("Search engine", engine),
            row("Include search engine suggestions", makeSwitch(p.suggestionsEnabled, #selector(suggestionsChanged(_:)))),
            row("Archive tabs", archive),
            row("Download location", dl),
        ])
        profileForm.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: profileForm.topAnchor),
            stack.leadingAnchor.constraint(equalTo: profileForm.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: profileForm.trailingAnchor),
        ])
    }

    @objc private func addProfile() {
        guard let host else { return }
        selectedProfileId = host.settingsAddProfile().id
        rebuildProfileBar(); rebuildProfileForm()
    }
    @objc private func removeProfile() {
        guard let host, let pid = selectedProfileId else { return }
        if host.settingsRemoveProfile(pid) {
            selectedProfileId = host.settingsProfiles().first?.id
            rebuildProfileBar(); rebuildProfileForm()
        } else { NSSound.beep() }
    }
    @objc private func renameProfile() {
        guard let host, let pid = selectedProfileId, let p = host.settingsProfiles().first(where: { $0.id == pid }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Profile"
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = p.name; alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        host.settingsRenameProfile(pid, to: field.stringValue)
        rebuildProfileBar(); rebuildProfileForm()
    }
    @objc private func engineChanged(_ s: NSPopUpButton) {
        guard let pid = selectedProfileId, s.indexOfSelectedItem < SearchEngine.allCases.count else { return }
        let e = SearchEngine.allCases[s.indexOfSelectedItem]
        host?.settingsUpdateProfile(pid) { $0.searchEngineRaw = e.rawValue }
    }
    @objc private func suggestionsChanged(_ s: NSSwitch) {
        guard let pid = selectedProfileId else { return }
        host?.settingsUpdateProfile(pid) { $0.searchSuggestions = (s.state == .on) }
    }
    @objc private func archiveChanged(_ s: NSPopUpButton) {
        guard let pid = selectedProfileId, s.indexOfSelectedItem < AutoArchive.allCases.count else { return }
        let a = AutoArchive.allCases[s.indexOfSelectedItem]
        host?.settingsUpdateProfile(pid) { $0.autoArchiveRaw = a.rawValue }
    }
    @objc private func chooseDownloadFolder() {
        guard let pid = selectedProfileId else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        host?.settingsUpdateProfile(pid) { $0.downloadPath = url.path }
        rebuildProfileForm()
    }

    // MARK: Shortcuts (remappable)

    private func shortcutsView() -> NSView {
        let v = NSView()
        let title = heading("Shortcuts")
        let hint = NSTextField(labelWithString: "Click a shortcut to record a new one · Delete to reset · Esc to cancel")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor

        let rows = ShortcutAction.allCases.map { a -> NSView in
            let rec = ShortcutRecorder(); rec.configure(a)
            rec.widthAnchor.constraint(equalToConstant: 130).isActive = true
            return row(a.title, rec)
        }
        let stack = formStack(rows)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView(); doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack); scroll.documentView = doc

        for s in [title, hint, scroll] { s.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(s) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            hint.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -24),
            scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -24),
            doc.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -4),
        ])
        return v
    }

    // MARK: Routing (Air Traffic Control)

    private func routingView() -> NSView {
        let v = NSView()
        let title = heading("Link Routing")
        let hint = NSTextField(labelWithString: "Open links from other apps in a chosen space (and its profile). Unmatched links open in a Quick Look.")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping; hint.maximumNumberOfLines = 2
        hint.preferredMaxLayoutWidth = 620

        routingList.orientation = .vertical
        routingList.alignment = .leading
        routingList.spacing = 8
        routingList.translatesAutoresizingMaskIntoConstraints = false

        let add = NSButton(title: "Add Rule", image: NSImage(systemSymbolName: "plus", accessibilityDescription: nil)!, target: self, action: #selector(addRule))
        add.imagePosition = .imageLeading; add.bezelStyle = .rounded; add.controlSize = .regular

        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView(); doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(routingList); scroll.documentView = doc

        for s in [title, hint, add, scroll] { s.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(s) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            hint.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -24),
            add.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            add.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            scroll.topAnchor.constraint(equalTo: add.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -24),
            scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -24),
            doc.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            routingList.topAnchor.constraint(equalTo: doc.topAnchor, constant: 2),
            routingList.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            routingList.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            routingList.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -2),
        ])
        rebuildRoutingList()
        return v
    }

    private func rebuildRoutingList() {
        routingList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let host else { return }
        let spaces = host.settingsWorkspacePicker()
        let rules = host.settingsRoutingRules()
        if rules.isEmpty {
            let empty = NSTextField(labelWithString: "No rules yet — add one to route a site to a space.")
            empty.font = .systemFont(ofSize: 12); empty.textColor = .tertiaryLabelColor
            routingList.addArrangedSubview(empty)
            return
        }
        for rule in rules {
            routingList.addArrangedSubview(ruleRow(rule, spaces))
        }
    }

    private func ruleRow(_ rule: RoutingRule, _ spaces: [(id: UUID, name: String)]) -> NSView {
        let r = NSView()
        r.translatesAutoresizingMaskIntoConstraints = false

        let hostField = NSTextField(string: rule.host)
        hostField.placeholderString = "example.com"
        hostField.font = .systemFont(ofSize: 13)
        hostField.identifier = NSUserInterfaceItemIdentifier(rule.id.uuidString)
        hostField.target = self; hostField.action = #selector(ruleHostChanged(_:))
        hostField.translatesAutoresizingMaskIntoConstraints = false

        let arrow = NSTextField(labelWithString: "→")
        arrow.font = .systemFont(ofSize: 13); arrow.textColor = .secondaryLabelColor
        arrow.translatesAutoresizingMaskIntoConstraints = false

        let popup = NSPopUpButton()
        popup.addItems(withTitles: spaces.map { $0.name })
        if let idx = spaces.firstIndex(where: { $0.id == rule.workspaceId }) { popup.selectItem(at: idx) }
        popup.identifier = NSUserInterfaceItemIdentifier(rule.id.uuidString)
        popup.target = self; popup.action = #selector(ruleSpaceChanged(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false

        let remove = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))!,
                              target: self, action: #selector(removeRule(_:)))
        remove.bezelStyle = .rounded; remove.controlSize = .regular
        remove.contentTintColor = .systemRed
        remove.identifier = NSUserInterfaceItemIdentifier(rule.id.uuidString)
        remove.translatesAutoresizingMaskIntoConstraints = false

        r.addSubview(hostField); r.addSubview(arrow); r.addSubview(popup); r.addSubview(remove)
        NSLayoutConstraint.activate([
            r.heightAnchor.constraint(equalToConstant: 28),
            hostField.leadingAnchor.constraint(equalTo: r.leadingAnchor),
            hostField.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            hostField.widthAnchor.constraint(equalToConstant: 220),
            arrow.leadingAnchor.constraint(equalTo: hostField.trailingAnchor, constant: 10),
            arrow.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            popup.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 10),
            popup.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            remove.leadingAnchor.constraint(equalTo: popup.trailingAnchor, constant: 12),
            remove.trailingAnchor.constraint(equalTo: r.trailingAnchor),
            remove.widthAnchor.constraint(equalToConstant: 40),
            remove.centerYAnchor.constraint(equalTo: r.centerYAnchor),
        ])
        return r
    }

    private func ruleId(_ sender: NSView) -> UUID? {
        guard let raw = sender.identifier?.rawValue else { return nil }
        return UUID(uuidString: raw)
    }
    @objc private func addRule() { host?.settingsAddRule(); rebuildRoutingList() }
    @objc private func removeRule(_ s: NSButton) {
        guard let id = ruleId(s) else { return }
        host?.settingsRemoveRule(id); rebuildRoutingList()
    }
    @objc private func ruleHostChanged(_ s: NSTextField) {
        guard let id = ruleId(s) else { return }
        host?.settingsUpdateRule(id, host: s.stringValue)
    }
    @objc private func ruleSpaceChanged(_ s: NSPopUpButton) {
        guard let id = ruleId(s), let host else { return }
        let spaces = host.settingsWorkspacePicker()
        guard s.indexOfSelectedItem < spaces.count else { return }
        host.settingsUpdateRule(id, workspaceId: spaces[s.indexOfSelectedItem].id)
    }

    // MARK: Advanced

    private func advancedView() -> NSView {
        let v = NSView()
        let title = heading("Advanced")
        let hint = NSTextField(labelWithString: "Nothing here yet.")
        hint.font = .systemFont(ofSize: 13); hint.textColor = .secondaryLabelColor
        for s in [title, hint] { s.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(s) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
        ])
        return v
    }
}

/// A clickable row/chip.
private final class ProfileRow: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}
