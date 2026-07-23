import Foundation

/// Settings for the status bar above the web content. Extensible — weather is the first status; more
/// can be added later.
enum StatusBarSettings {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "muninn.statusbar.enabled") }   // default off
        set { UserDefaults.standard.set(newValue, forKey: "muninn.statusbar.enabled") }
    }
    /// City for the weather status. Defaults to Montreal.
    static var city: String {
        get {
            let v = (UserDefaults.standard.string(forKey: "muninn.statusbar.city") ?? "").trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? "Montreal" : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "muninn.statusbar.city") }
    }
    static var fahrenheit: Bool {
        get { UserDefaults.standard.bool(forKey: "muninn.statusbar.fahrenheit") }
        set { UserDefaults.standard.set(newValue, forKey: "muninn.statusbar.fahrenheit") }
    }
}
