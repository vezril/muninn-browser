import AppKit

/// The right-hand Tools sidebar: a workspace-tinted panel hosting a set of tool widgets with a
/// compact switcher at the top (Calendar / Ask / …). Mirrors the left sidebar's visual language.
@MainActor
final class ToolsSidebar: NSView {
    struct Tool { let id: String; let title: String; let symbol: String; let view: NSView }

    private(set) var selectedId: String?
    private var tools: [Tool] = []
    private var buttons: [String: NSButton] = [:]

    private let switcher = NSStackView()
    private let container = NSView()
    private let emptyLabel = NSTextField(labelWithString: "No tools yet.")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        switcher.orientation = .horizontal
        switcher.spacing = 4
        switcher.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 12); emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(switcher); addSubview(container); addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            switcher.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            switcher.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            switcher.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: switcher.bottomAnchor, constant: 10),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    /// Install the tools + switcher. Keeps the current selection if still present.
    func setTools(_ tools: [Tool], select: String? = nil) {
        self.tools = tools
        switcher.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        for t in tools {
            let b = NSButton(image: NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title)
                                ?? NSImage(), target: self, action: #selector(switchTapped(_:)))
            b.isBordered = false
            b.toolTip = t.title
            b.imageScaling = .scaleProportionallyDown
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.identifier = NSUserInterfaceItemIdentifier(t.id)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 34).isActive = true
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
            buttons[t.id] = b
            switcher.addArrangedSubview(b)
        }
        switcher.isHidden = tools.count < 2 // one tool → no switcher needed
        let target = select ?? selectedId ?? tools.first?.id
        selectTool(target)
    }

    @objc private func switchTapped(_ sender: NSButton) { selectTool(sender.identifier?.rawValue) }

    /// Show the tool with `id` (nil / unknown → empty state).
    func selectTool(_ id: String?) {
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let id, let tool = tools.first(where: { $0.id == id }) else {
            selectedId = nil; emptyLabel.isHidden = tools.isEmpty ? false : true; highlight(nil); return
        }
        selectedId = id
        emptyLabel.isHidden = true
        let v = tool.view
        v.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: container.topAnchor),
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        highlight(id)
    }

    private func highlight(_ id: String?) {
        for (bid, b) in buttons {
            let on = bid == id
            b.layer?.backgroundColor = (on ? NSColor.controlAccentColor.withAlphaComponent(0.22) : .clear).cgColor
            b.contentTintColor = on ? .controlAccentColor : .secondaryLabelColor
        }
    }

    func applyTint(_ color: NSColor) { layer?.backgroundColor = color.cgColor }
}
