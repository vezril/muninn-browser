import AppKit

/// The "Ask" tool: a non-blocking chat with the local model, living in the Tools sidebar.
/// Persists sessions (survives window close), with New Session / Clear and a session switcher.
@MainActor
final class AskChatView: NSView {
    /// Runs a chat turn: given the full message history, stream tokens then finish (nil = ok).
    var runChat: (([ChatMessage], _ onToken: @escaping (String) -> Void, _ onDone: @escaping (Error?) -> Void) -> Void)?
    /// The current page's context (title/url/visible text), when the page toggle is on.
    struct PageContext { let title: String; let url: String; let text: String }
    var fetchPageContext: ((@escaping (PageContext?) -> Void) -> Void)?
    private var includePage = false

    private let store = ChatStore()
    private var sessions: [ChatSession] = []
    private var current = 0

    private let sessionPopup = NSPopUpButton()
    private let messagesStack = NSStackView()
    private let scroll = NSScrollView()
    private let input = NSTextField()
    private let pageToggle = NSButton()
    private var streamingLabel: NSTextField?   // the assistant bubble being streamed into
    private var isStreaming = false
    private var typingTimer: Timer?
    private var typingDots = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: layout

    private func build() {
        // Top bar: session switcher + New + Clear.
        sessionPopup.target = self; sessionPopup.action = #selector(switchSession)
        sessionPopup.controlSize = .small
        sessionPopup.translatesAutoresizingMaskIntoConstraints = false
        let newBtn = iconButton("square.and.pencil", #selector(newSession), "New session")
        let clearBtn = iconButton("trash", #selector(clearSession), "Clear this session")
        let bar = NSStackView(views: [sessionPopup, newBtn, clearBtn])
        bar.orientation = .horizontal; bar.spacing = 4
        bar.setHuggingPriority(.defaultLow, for: .horizontal)
        sessionPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.translatesAutoresizingMaskIntoConstraints = false

        messagesStack.orientation = .vertical
        messagesStack.alignment = .leading
        messagesStack.spacing = 8
        messagesStack.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(messagesStack)
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        input.placeholderString = "Message the local model…"
        input.font = .systemFont(ofSize: 13)
        input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false

        // Page-context toggle, left of the input.
        pageToggle.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Include page")
        pageToggle.isBordered = false
        pageToggle.contentTintColor = .secondaryLabelColor
        pageToggle.toolTip = "Include the current page as context"
        pageToggle.target = self; pageToggle.action = #selector(togglePage)
        pageToggle.translatesAutoresizingMaskIntoConstraints = false
        pageToggle.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let inputRow = NSStackView(views: [pageToggle, input])
        inputRow.orientation = .horizontal; inputRow.spacing = 4
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(bar); addSubview(scroll); addSubview(inputRow)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),

            inputRow.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            inputRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            messagesStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            messagesStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 4),
            messagesStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -4),
            messagesStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -4),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), // clip width, not frame (excludes the scroller)
        ])
    }

    private func iconButton(_ symbol: String, _ action: Selector, _ tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.isBordered = false; b.toolTip = tip; b.contentTintColor = .secondaryLabelColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    // MARK: sessions

    private func reload() {
        sessions = store.load()
        if sessions.isEmpty { sessions = [ChatSession()] }
        current = 0 // most-recently-saved first (we keep newest at front)
        rebuildSessionPopup()
        renderMessages()
    }

    private func rebuildSessionPopup() {
        sessionPopup.removeAllItems()
        for s in sessions { sessionPopup.addItem(withTitle: s.title.isEmpty ? "New Chat" : s.title) }
        if sessions.indices.contains(current) { sessionPopup.selectItem(at: current) }
    }

    @objc private func switchSession() {
        guard !isStreaming else { NSSound.beep(); return }
        current = sessionPopup.indexOfSelectedItem
        renderMessages()
    }

    @objc private func newSession() {
        guard !isStreaming else { NSSound.beep(); return }
        sessions.insert(ChatSession(), at: 0)
        current = 0
        persist(); rebuildSessionPopup(); renderMessages()
        window?.makeFirstResponder(input)
    }

    @objc private func clearSession() {
        guard !isStreaming, sessions.indices.contains(current) else { NSSound.beep(); return }
        sessions[current].messages.removeAll()
        sessions[current].title = "New Chat"
        persist(); rebuildSessionPopup(); renderMessages()
    }

    private func persist() {
        if sessions.indices.contains(current) { sessions[current].updatedAt = Date() }
        store.save(sessions)
    }

    // MARK: rendering

    private func renderMessages() {
        messagesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard sessions.indices.contains(current) else { return }
        for m in sessions[current].messages {
            let row = bubble(for: m.role, text: m.text)
            messagesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: messagesStack.widthAnchor).isActive = true // safe: now share an ancestor
        }
        scrollToBottom()
    }

    private func bubble(for role: ChatMessage.Role, text: String) -> NSView {
        let isUser = role == .user
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 9
        card.layer?.backgroundColor = (isUser ? NSColor.controlAccentColor.withAlphaComponent(0.9)
                                              : NSColor.textBackgroundColor.withAlphaComponent(0.6)).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = isUser ? .white : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -7),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -9),
        ])
        if !isUser { streamingLabel = label } // most-recent assistant bubble is the stream target

        // Row spans the column; the card hugs left (assistant) or right (user), max 90% wide.
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: row.topAnchor),
            card.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.9),
            isUser ? card.trailingAnchor.constraint(equalTo: row.trailingAnchor)
                   : card.leadingAnchor.constraint(equalTo: row.leadingAnchor),
        ])
        return row // row-to-stack width constraint is added by the caller after insertion
    }

    private func scrollToBottom() {
        layoutSubtreeIfNeeded()
        if let doc = scroll.documentView { doc.scroll(NSPoint(x: 0, y: doc.bounds.height)) }
    }

    // MARK: sending

    private func send() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, sessions.indices.contains(current) else { return }
        input.stringValue = ""
        sessions[current].messages.append(ChatMessage(role: .user, text: text))
        sessions[current].messages.append(ChatMessage(role: .assistant, text: ""))
        sessions[current].retitle()
        rebuildSessionPopup()
        renderMessages()
        persist()

        isStreaming = true
        startTyping()
        let history = Array(sessions[current].messages.dropLast()) // exclude the empty assistant placeholder

        // With the page toggle on, fetch the current page and prepend it as a system message.
        if includePage, let fetch = fetchPageContext {
            fetch { [weak self] ctx in
                guard let self else { return }
                var payload = history
                if let ctx, !ctx.text.isEmpty {
                    payload.insert(ChatMessage(role: .system, text: Self.pageSystemPrompt(ctx)), at: 0)
                }
                self.stream(payload)
            }
        } else {
            stream(history)
        }
    }

    private func stream(_ payload: [ChatMessage]) {
        runChat?(payload, { [weak self] token in self?.appendToken(token) },
                          { [weak self] error in self?.finishStream(error) })
    }

    private static func pageSystemPrompt(_ ctx: PageContext) -> String {
        """
        The user is viewing this web page. Use its content to answer their question.

        Title: \(ctx.title)
        URL: \(ctx.url)

        \(ctx.text)
        """
    }

    @objc private func togglePage() {
        includePage.toggle()
        pageToggle.contentTintColor = includePage ? .controlAccentColor : .secondaryLabelColor
    }

    /// Animate "." → ".." → "..." in the pending assistant bubble until the first token.
    private func startTyping() {
        typingDots = 1
        streamingLabel?.stringValue = "."
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let label = self.streamingLabel else { return }
                self.typingDots = self.typingDots % 3 + 1
                label.stringValue = String(repeating: ".", count: self.typingDots)
            }
        }
    }
    private func stopTyping() { typingTimer?.invalidate(); typingTimer = nil }

    private func appendToken(_ token: String) {
        stopTyping() // first real text replaces the dots
        guard sessions.indices.contains(current), let last = sessions[current].messages.indices.last else { return }
        sessions[current].messages[last].text += token
        streamingLabel?.stringValue = sessions[current].messages[last].text
        scrollToBottom()
    }

    private func finishStream(_ error: Error?) {
        stopTyping()
        isStreaming = false
        if sessions.indices.contains(current), let last = sessions[current].messages.indices.last {
            if let error, sessions[current].messages[last].text.isEmpty {
                sessions[current].messages[last].text = "⚠️ \(error.localizedDescription)"
            }
            streamingLabel?.stringValue = sessions[current].messages[last].text // clear any lingering dots
        }
        persist()
    }

    /// Focus the input (called when the Ask tool is revealed).
    func focusInput() { window?.makeFirstResponder(input) }
}

extension AskChatView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { send(); return true }
        return false
    }
}

/// A top-left-origin container so the messages stack grows downward in the scroll view.
private final class FlippedView: NSView { override var isFlipped: Bool { true } }
