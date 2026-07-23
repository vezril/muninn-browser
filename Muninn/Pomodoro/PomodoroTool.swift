import AppKit
import UserNotifications

/// The Pomodoro tool (Tools sidebar): a progress ring with the countdown, Start/Pause/Reset/Skip,
/// session dots, and an inline "Customize" panel for durations + auto-start. The engine keeps ticking
/// even when the tool isn't the visible tab (the view is retained by the shell). On phase completion it
/// plays a sound and calls `onPhaseComplete` (the shell shows a toast).
@MainActor
final class PomodoroTool: NSView {
    /// Called when a phase finishes: (endedPhase, nextPhase).
    var onPhaseComplete: ((PomodoroPhase, PomodoroPhase) -> Void)?

    private let engine = PomodoroEngine(config: PomodoroSettings.config)
    private var timer: Timer?
    private var requestedNotifAuth = false

    private let ring = PomodoroRingView()
    private let dots = NSStackView()
    private let startButton = NSButton()
    private let customizeButton = NSButton()
    private let customPanel = NSStackView()
    private var focusStepper: LabeledStepper!
    private var shortStepper: LabeledStepper!
    private var longStepper: LabeledStepper!
    private var everyStepper: LabeledStepper!
    private let autoStart = NSButton(checkboxWithTitle: "Auto-start next", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: build

    private func build() {
        customizeButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Customize")
        customizeButton.isBordered = false; customizeButton.contentTintColor = .secondaryLabelColor
        customizeButton.target = self; customizeButton.action = #selector(toggleCustomize)
        customizeButton.toolTip = "Customize durations"
        customizeButton.translatesAutoresizingMaskIntoConstraints = false
        let topRow = NSStackView(views: [NSView(), customizeButton])
        topRow.orientation = .horizontal
        topRow.translatesAutoresizingMaskIntoConstraints = false

        ring.translatesAutoresizingMaskIntoConstraints = false

        dots.orientation = .horizontal; dots.spacing = 6; dots.alignment = .centerY
        dots.translatesAutoresizingMaskIntoConstraints = false

        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.target = self; startButton.action = #selector(startPause)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        let reset = iconButton("arrow.counterclockwise", #selector(reset), "Reset")
        let skip = iconButton("forward.end", #selector(skip), "Skip")
        let controls = NSStackView(views: [reset, startButton, skip])
        controls.orientation = .horizontal; controls.spacing = 12; controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false

        // Customize panel (hidden until toggled).
        focusStepper = LabeledStepper(title: "Focus", value: engine.config.focusMinutes, range: 1...120, unit: "min") { [weak self] _ in self?.commitConfig() }
        shortStepper = LabeledStepper(title: "Short break", value: engine.config.shortBreakMinutes, range: 1...60, unit: "min") { [weak self] _ in self?.commitConfig() }
        longStepper  = LabeledStepper(title: "Long break", value: engine.config.longBreakMinutes, range: 1...60, unit: "min") { [weak self] _ in self?.commitConfig() }
        everyStepper = LabeledStepper(title: "Long break every", value: engine.config.longBreakEvery, range: 2...12, unit: "") { [weak self] _ in self?.commitConfig() }
        autoStart.state = engine.config.autoStartNext ? .on : .off
        autoStart.target = self; autoStart.action = #selector(commitConfig)
        autoStart.font = .systemFont(ofSize: 12)
        autoStart.translatesAutoresizingMaskIntoConstraints = false
        customPanel.orientation = .vertical; customPanel.alignment = .leading; customPanel.spacing = 8
        for v in [focusStepper!, shortStepper!, longStepper!, everyStepper!] { customPanel.addArrangedSubview(v) }
        customPanel.addArrangedSubview(autoStart)
        customPanel.isHidden = true
        customPanel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [topRow, ring, dots, controls, customPanel])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 14
        stack.setCustomSpacing(10, after: ring)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            topRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            customPanel.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6),
            customPanel.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
            ring.widthAnchor.constraint(equalToConstant: 168),
            ring.heightAnchor.constraint(equalToConstant: 168),
        ])
    }

    private func iconButton(_ symbol: String, _ action: Selector, _ tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) ?? NSImage(),
                         target: self, action: action)
        b.isBordered = false; b.contentTintColor = .secondaryLabelColor; b.toolTip = tip
        return b
    }

    // MARK: actions

    private func onTick() {
        if let ended = engine.tick() {
            NSSound(named: ended == .focus ? "Glass" : "Ping")?.play()  // audio, foreground or background
            postNotification(ended: ended, next: engine.phase)          // OS banner when backgrounded
            onPhaseComplete?(ended, engine.phase)                       // in-app toast when foreground
        }
        refresh()
    }

    @objc private func startPause() {
        engine.toggle()
        if engine.isRunning { requestNotifAuthIfNeeded() }
        refresh()
    }

    /// Ask for notification permission once, the first time the user starts a timer.
    private func requestNotifAuthIfNeeded() {
        guard !requestedNotifAuth else { return }
        requestedNotifAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post an OS notification for a phase transition. Silent (NSSound handles audio); macOS suppresses
    /// it while Muninn is foreground — where the in-app toast covers it — and banners it when backgrounded.
    private func postNotification(ended: PomodoroPhase, next: PomodoroPhase) {
        let content = UNMutableNotificationContent()
        content.title = "\(ended.title) complete"
        content.body = "\(next.title) is up."
        content.sound = nil
        let req = UNNotificationRequest(identifier: "pomodoro-\(next.rawValue)-\(engine.completedFocus)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
    @objc private func reset() { engine.reset(); refresh() }
    @objc private func skip() { _ = engine.skip(); refresh() }
    @objc private func toggleCustomize() {
        customPanel.isHidden.toggle()
        customizeButton.contentTintColor = customPanel.isHidden ? .secondaryLabelColor : .controlAccentColor
    }

    @objc private func commitConfig() {
        let c = PomodoroConfig(focusMinutes: focusStepper.value, shortBreakMinutes: shortStepper.value,
                               longBreakMinutes: longStepper.value, longBreakEvery: everyStepper.value,
                               autoStartNext: autoStart.state == .on)
        PomodoroSettings.config = c
        engine.apply(c)
        refresh()
    }

    // MARK: render

    private func refresh() {
        let m = engine.remaining / 60, s = engine.remaining % 60
        ring.timeLabel.stringValue = String(format: "%02d:%02d", m, s)
        ring.phaseLabel.stringValue = engine.phase.title
        ring.setProgress(engine.elapsedFraction, color: color(for: engine.phase))
        startButton.title = engine.isRunning ? "Pause" : (engine.elapsedFraction > 0 ? "Resume" : "Start")
        renderDots()
    }

    private func color(for phase: PomodoroPhase) -> NSColor {
        switch phase {
        case .focus: return .controlAccentColor
        case .shortBreak: return .systemTeal
        case .longBreak: return .systemGreen
        }
    }

    /// Dots for the current set: filled = focus sessions done toward the next long break.
    private func renderDots() {
        dots.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let n = max(1, engine.config.longBreakEvery)
        let done = engine.completedFocus % n   // 0…n-1 within the current set
        for i in 0..<n {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.backgroundColor = (i < done ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor.withAlphaComponent(0.4)).cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            dots.addArrangedSubview(dot)
        }
    }
}

/// A "Title  [stepper]  N unit" row.
@MainActor
private final class LabeledStepper: NSView {
    private let stepper = NSStepper()
    private let valueLabel = NSTextField(labelWithString: "")
    private let unit: String
    private let onChange: (Int) -> Void
    var value: Int { stepper.integerValue }

    init(title: String, value: Int, range: ClosedRange<Int>, unit: String, onChange: @escaping (Int) -> Void) {
        self.unit = unit; self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 12)
        name.translatesAutoresizingMaskIntoConstraints = false
        stepper.minValue = Double(range.lowerBound); stepper.maxValue = Double(range.upperBound)
        stepper.integerValue = value; stepper.valueWraps = false
        stepper.target = self; stepper.action = #selector(changed)
        stepper.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        updateLabel()
        addSubview(name); addSubview(valueLabel); addSubview(stepper)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            name.leadingAnchor.constraint(equalTo: leadingAnchor),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            stepper.trailingAnchor.constraint(equalTo: trailingAnchor),
            stepper.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: stepper.leadingAnchor, constant: -6),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 46),
            name.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -6),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateLabel() { valueLabel.stringValue = unit.isEmpty ? "\(stepper.integerValue)" : "\(stepper.integerValue) \(unit)" }
    @objc private func changed() { updateLabel(); onChange(stepper.integerValue) }
}

/// A circular progress ring with the time + phase label centred.
@MainActor
private final class PomodoroRingView: NSView {
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    let timeLabel = NSTextField(labelWithString: "25:00")
    let phaseLabel = NSTextField(labelWithString: "Focus")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for l in [track, progress] {
            l.fillColor = NSColor.clear.cgColor; l.lineWidth = 9; l.lineCap = .round
            layer?.addSublayer(l)
        }
        track.strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(0.18).cgColor
        progress.strokeColor = NSColor.controlAccentColor.cgColor
        progress.strokeEnd = 0

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        timeLabel.alignment = .center; timeLabel.textColor = .labelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        phaseLabel.font = .systemFont(ofSize: 12, weight: .medium)
        phaseLabel.alignment = .center; phaseLabel.textColor = .secondaryLabelColor
        phaseLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel); addSubview(phaseLabel)
        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            phaseLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            phaseLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 0),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - inset
        // Start at top (π/2), sweep clockwise so strokeEnd fills like a clock.
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        track.path = path; progress.path = path
    }

    func setProgress(_ fraction: Double, color: NSColor) {
        progress.strokeColor = color.cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)  // no implicit animation each tick
        progress.strokeEnd = CGFloat(min(max(fraction, 0), 1))
        CATransaction.commit()
    }
}
