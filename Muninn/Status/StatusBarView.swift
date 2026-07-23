import AppKit

/// A compact status bar shown in the strip above the web card. Currently weather (city · temperature ·
/// humidity · AQI); built as a row of icon+text chips so more statuses can be added later.
@MainActor
final class StatusBarView: NSView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setLoading() { rebuild([("ellipsis", "…", .secondaryLabelColor)]) }

    func update(_ s: WeatherSnapshot?, fahrenheit: Bool) {
        guard let s else { rebuild([("cloud.slash", "Weather unavailable", .secondaryLabelColor)]); return }
        let temp = fahrenheit ? s.tempC * 9 / 5 + 32 : s.tempC
        let unit = fahrenheit ? "°F" : "°C"
        var chips: [(String, String, NSColor)] = [
            ("location.fill", s.city, .secondaryLabelColor),
            ("thermometer.medium", "\(Int(temp.rounded()))\(unit)", .labelColor),
            ("humidity.fill", "\(s.humidity)%", .labelColor),
        ]
        if let aqi = s.aqi { chips.append(("aqi.medium", "AQI \(aqi)", Self.aqiColor(aqi))) }
        rebuild(chips)
    }

    private func rebuild(_ chips: [(symbol: String, text: String, color: NSColor)]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for c in chips { stack.addArrangedSubview(chip(symbol: c.symbol, text: c.text, color: c.color)) }
    }

    private func chip(symbol: String, text: String, color: NSColor) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)) ?? NSImage())
        icon.contentTintColor = color
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = color
        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal; row.spacing = 4; row.alignment = .centerY
        return row
    }

    /// US AQI band colours (0–50 good … 301+ hazardous).
    nonisolated static func aqiColor(_ aqi: Int) -> NSColor {
        switch aqi {
        case ..<51: return .systemGreen
        case ..<101: return .systemYellow
        case ..<151: return .systemOrange
        case ..<201: return .systemRed
        case ..<301: return .systemPurple
        default: return .systemBrown
        }
    }
}
