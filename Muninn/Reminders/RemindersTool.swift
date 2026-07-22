import AppKit
import EventKit

/// The Reminders tool (Tools sidebar): pick a list, see its reminders, check them off, edit, delete,
/// and add new ones. Backed by `RemindersService` (EventKit, on-device). Requests Reminders access the
/// first time it's shown. Observes `.EKEventStoreChanged` so external edits (or our own commands)
/// refresh live.
@MainActor
final class RemindersTool: NSView {
    private let service = RemindersService.shared

    private let listPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let newListButton = NSButton()
    private let showCompleted = NSButton(checkboxWithTitle: "Completed", target: nil, action: nil)
    private let scroll = NSScrollView()
    private let rows = NSStackView()
    private let addField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    private var lists: [ReminderList] = []
    private var items: [ReminderItem] = []
    private var selectedListId: String?
    private var activated = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: .EKEventStoreChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: build

    private func build() {
        listPopup.target = self; listPopup.action = #selector(listChanged)
        listPopup.translatesAutoresizingMaskIntoConstraints = false

        newListButton.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "New List")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        newListButton.imagePosition = .imageOnly
        newListButton.bezelStyle = .regularSquare
        newListButton.isBordered = false
        newListButton.contentTintColor = .controlAccentColor
        newListButton.target = self; newListButton.action = #selector(newListTapped)
        newListButton.toolTip = "New List…"
        newListButton.translatesAutoresizingMaskIntoConstraints = false
        newListButton.setContentHuggingPriority(.required, for: .horizontal)
        newListButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The popup fills the row; the button keeps its own width at the trailing edge.
        listPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        listPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        showCompleted.target = self; showCompleted.action = #selector(reloadItems)
        showCompleted.font = .systemFont(ofSize: 11)
        showCompleted.controlSize = .small
        showCompleted.translatesAutoresizingMaskIntoConstraints = false

        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 4
        rows.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(rows)
        scroll.documentView = doc; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .center; statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        addField.placeholderString = "Add a reminder…"
        addField.font = .systemFont(ofSize: 12)
        addField.target = self; addField.action = #selector(addTapped)
        addField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(listPopup); addSubview(newListButton)
        addSubview(showCompleted); addSubview(scroll); addSubview(statusLabel); addSubview(addField)
        NSLayoutConstraint.activate([
            listPopup.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            listPopup.leadingAnchor.constraint(equalTo: leadingAnchor),
            listPopup.trailingAnchor.constraint(equalTo: newListButton.leadingAnchor, constant: -6),
            newListButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            newListButton.centerYAnchor.constraint(equalTo: listPopup.centerYAnchor),
            newListButton.widthAnchor.constraint(equalToConstant: 22),
            newListButton.heightAnchor.constraint(equalToConstant: 22),
            showCompleted.topAnchor.constraint(equalTo: listPopup.bottomAnchor, constant: 6),
            showCompleted.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            scroll.topAnchor.constraint(equalTo: showCompleted.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: addField.topAnchor, constant: -8),
            rows.topAnchor.constraint(equalTo: doc.topAnchor, constant: 2),
            rows.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 2),
            rows.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -2),
            rows.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -4),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            addField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            addField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            addField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    // MARK: activation / permission

    /// Shown for the first time → ensure access and load. Re-shown → refresh.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        if !activated { activated = true; Task { await self.ensureAccessAndLoad() } }
        else { reloadItems() }
    }

    private func ensureAccessAndLoad() async {
        switch service.status {
        case .fullAccess:
            loadLists()
        case .notDetermined:
            let granted = await service.requestAccess()
            if granted { loadLists() } else { showStatus("Reminders access was declined. Enable it in System Settings › Privacy & Security › Reminders.") }
        default:
            showStatus("Muninn doesn't have Reminders access. Enable it in System Settings › Privacy & Security › Reminders.")
        }
    }

    // MARK: data

    /// Reload the list popup (call after permission or when lists change).
    func loadLists() {
        lists = service.lists()
        listPopup.removeAllItems()
        for l in lists { listPopup.addItem(withTitle: l.title) }
        guard !lists.isEmpty else { showStatus("No reminder lists yet. Tap ＋ to create one."); return }
        if selectedListId == nil || !lists.contains(where: { $0.id == selectedListId }) {
            selectedListId = service.defaultListId().flatMap { id in lists.first { $0.id == id }?.id } ?? lists.first?.id
        }
        if let sel = selectedListId, let idx = lists.firstIndex(where: { $0.id == sel }) {
            listPopup.selectItem(at: idx)
        }
        reloadItems()
    }

    /// Programmatically focus a list (used after "Create List from Page").
    func focusList(id: String) {
        selectedListId = id
        loadLists()
    }

    @objc private func reloadItems() {
        guard let id = selectedListId else { return }
        let include = showCompleted.state == .on
        Task {
            let fetched = await service.reminders(inListId: id, includeCompleted: include)
            self.items = fetched
            self.renderRows()
        }
    }

    private func renderRows() {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if items.isEmpty {
            showStatus(showCompleted.state == .on ? "No reminders in this list." : "All done — no open reminders.")
            return
        }
        statusLabel.isHidden = true; scroll.isHidden = false
        for item in items {
            let row = RemindersRow(item: item,
                                   onToggle: { [weak self] done in self?.toggle(item, done: done) },
                                   onEdit: { [weak self] in self?.edit(item) },
                                   onDelete: { [weak self] in self?.delete(item) })
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    private func showStatus(_ text: String) {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statusLabel.stringValue = text
        statusLabel.isHidden = false
        scroll.isHidden = false // keep the scroll frame; status is centered over it
    }

    // MARK: actions

    @objc private func listChanged() {
        let idx = listPopup.indexOfSelectedItem
        guard idx >= 0, idx < lists.count else { return }
        selectedListId = lists[idx].id
        reloadItems()
    }

    @objc private func storeChanged() { if activated, service.authorized { loadLists() } }

    @objc private func addTapped() {
        let title = addField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let id = selectedListId else { return }
        addField.stringValue = ""
        do { try service.createReminder(title: title, inListId: id); reloadItems() }
        catch { NSSound.beep() }
    }

    @objc private func newListTapped() {
        guard let name = promptText(title: "New Reminder List", message: "Name for the new list:", initial: "") else { return }
        do { let id = try service.createList(named: name); selectedListId = id; loadLists() }
        catch { presentError("Couldn't create the list.") }
    }

    private func toggle(_ item: ReminderItem, done: Bool) {
        do {
            try service.setCompleted(done, id: item.id)
            // If hiding completed, drop it; else re-fetch to restyle.
            if !done || showCompleted.state == .on { reloadItems() }
            else { items.removeAll { $0.id == item.id }; renderRows() }
        } catch { NSSound.beep(); reloadItems() }
    }

    private func edit(_ item: ReminderItem) {
        guard let newTitle = promptText(title: "Edit Reminder", message: "Title:", initial: item.title) else { return }
        do { try service.update(id: item.id, title: newTitle, notes: item.notes); reloadItems() }
        catch { presentError("Couldn't update the reminder.") }
    }

    private func delete(_ item: ReminderItem) {
        do { try service.delete(id: item.id); items.removeAll { $0.id == item.id }; renderRows() }
        catch { NSSound.beep() }
    }

    // MARK: small helpers (local so the tool is self-contained)

    private func promptText(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private func presentError(_ text: String) {
        let a = NSAlert(); a.messageText = text; a.addButton(withTitle: "OK"); a.runModal()
    }
}

/// One reminder row: a completion checkbox, the title (click to edit), and a hover-revealed delete.
@MainActor
private final class RemindersRow: NSView {
    private let onToggle: (Bool) -> Void
    private let onEdit: () -> Void
    private let onDelete: () -> Void
    private let deleteButton = NSButton()
    private let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(item: ReminderItem, onToggle: @escaping (Bool) -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.onToggle = onToggle; self.onEdit = onEdit; self.onDelete = onDelete
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        check.state = item.completed ? .on : .off
        check.target = self; check.action = #selector(checkTapped)
        check.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: item.title.isEmpty ? "(no title)" : item.title)
        title.font = .systemFont(ofSize: 12)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 2
        title.translatesAutoresizingMaskIntoConstraints = false
        if item.completed {
            title.attributedStringValue = NSAttributedString(string: title.stringValue, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])
        }
        let click = NSClickGestureRecognizer(target: self, action: #selector(editTapped))
        title.addGestureRecognizer(click)

        deleteButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Delete")
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .tertiaryLabelColor
        deleteButton.target = self; deleteButton.action = #selector(deleteTapped)
        deleteButton.isHidden = true
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(check); addSubview(title); addSubview(deleteButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 4),
            title.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let track = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                   owner: self, userInfo: nil)
        addTrackingArea(track)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { deleteButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { deleteButton.isHidden = true }
    @objc private func checkTapped() { onToggle(check.state == .on) }
    @objc private func editTapped() { onEdit() }
    @objc private func deleteTapped() { onDelete() }
}

/// Top-anchored flipped container for the scroll's document view.
private final class FlippedView: NSView { override var isFlipped: Bool { true } }
