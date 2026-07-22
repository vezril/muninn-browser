import AppKit

/// One tab's live resource snapshot for the Task Manager.
struct TaskManagerRow {
    let tabId: Int
    let title: String
    let favicon: NSImage?
    let pid: pid_t
    let memoryMB: Double
    let responsive: Bool
    let isActive: Bool
}

/// A Chrome-style Task Manager: a window listing each loaded tab with its WebContent process's
/// memory + responsiveness, refreshed every 2s. Double-click (or "Switch to Tab") focuses a tab;
/// "Reload" / "Close Tab" act on the selection (useful for a hung tab).
@MainActor
final class TaskManagerWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let window: NSWindow
    private let table = NSTableView()
    private var rows: [TaskManagerRow] = []
    private var timer: Timer?

    /// Live data + actions supplied by the shell.
    var provider: (() -> [TaskManagerRow])?
    var onSelect: ((Int) -> Void)?
    var onReload: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Task Manager"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 460, height: 260)
        super.init()
        window.delegate = self
        buildUI()
    }

    func present() {
        refresh()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil }

    // MARK: UI

    private func buildUI() {
        let root = NSView()

        func column(_ id: String, _ title: String, width: CGFloat) -> NSTableColumn {
            let c = NSTableColumn(identifier: .init(id)); c.title = title; c.width = width; return c
        }
        table.addTableColumn(column("tab", "Tab", width: 300))
        table.addTableColumn(column("mem", "Memory", width: 90))
        table.addTableColumn(column("status", "Status", width: 110))
        table.addTableColumn(column("pid", "PID", width: 60))
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 24
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(switchSelected)
        table.allowsMultipleSelection = false

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let switchBtn = NSButton(title: "Switch to Tab", target: self, action: #selector(switchSelected))
        let reloadBtn = NSButton(title: "Reload", target: self, action: #selector(reloadSelected))
        let closeBtn = NSButton(title: "Close Tab", target: self, action: #selector(closeSelected))
        for b in [switchBtn, reloadBtn, closeBtn] { b.bezelStyle = .rounded }
        closeBtn.contentTintColor = .systemRed
        let bar = NSStackView(views: [switchBtn, reloadBtn, closeBtn])
        bar.orientation = .horizontal; bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(scroll); root.addSubview(bar)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        window.contentView = root
    }

    // MARK: data

    private func refresh() {
        let prevSelectedTabId = selectedRow.map { rows[$0].tabId }
        rows = provider?() ?? []
        table.reloadData()
        if let id = prevSelectedTabId, let i = rows.firstIndex(where: { $0.tabId == id }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
    }

    private var selectedRow: Int? { table.selectedRow >= 0 && table.selectedRow < rows.count ? table.selectedRow : nil }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = rows[row]
        switch tableColumn?.identifier.rawValue {
        case "tab":
            let cell = NSView()
            let icon = NSImageView(image: r.favicon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!)
            icon.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: r.isActive ? "\(r.title)  ·  active" : r.title)
            label.lineBreakMode = .byTruncatingTail
            label.font = .systemFont(ofSize: 12, weight: r.isActive ? .semibold : .regular)
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon); cell.addSubview(label)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        case "mem":
            return textCell(String(format: "%.0f MB", r.memoryMB), align: .right)
        case "status":
            let tf = textCell(r.responsive ? "Responsive" : "Not responding", align: .left)
            tf.textColor = r.responsive ? .secondaryLabelColor : .systemRed
            return tf
        case "pid":
            return textCell("\(r.pid)", align: .right)
        default:
            return nil
        }
    }

    private func textCell(_ s: String, align: NSTextAlignment) -> NSTextField {
        let tf = NSTextField(labelWithString: s)
        tf.font = .systemFont(ofSize: 12)
        tf.alignment = align
        return tf
    }

    // MARK: actions

    @objc private func switchSelected() { if let i = selectedRow { onSelect?(rows[i].tabId) } }
    @objc private func reloadSelected() { if let i = selectedRow { onReload?(rows[i].tabId) } }
    @objc private func closeSelected() { if let i = selectedRow { onClose?(rows[i].tabId); refresh() } }
}
