import Foundation

/// The web search engine used by the address bar, command bar, and new-tab search.
enum SearchEngine: String, CaseIterable {
    case duckduckgo, google, bing

    var displayName: String {
        switch self {
        case .duckduckgo: return "DuckDuckGo"
        case .google:     return "Google"
        case .bing:       return "Bing"
        }
    }

    /// GET search endpoint (all use the `q` query param).
    var searchBase: String {
        switch self {
        case .duckduckgo: return "https://duckduckgo.com/"
        case .google:     return "https://www.google.com/search"
        case .bing:       return "https://www.bing.com/search"
        }
    }

    func url(_ query: String) -> URL {
        var c = URLComponents(string: searchBase)!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return c.url ?? URL(string: searchBase)!
    }

    // MARK: persisted setting

    private static let key = "muninn.searchEngine"
    static var current: SearchEngine {
        get { SearchEngine(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .duckduckgo }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Auto-Archive: how long a regular tab can sit unused before it's auto-closed (pinned/
/// favourite tabs are exempt). Archived tabs stay reopenable via Cmd+Shift+T / history.
enum AutoArchive: String, CaseIterable {
    case never, h12, d1, d7, d30

    var displayName: String {
        switch self {
        case .never: return "Never"
        case .h12:   return "After 12 Hours"
        case .d1:    return "After 1 Day"
        case .d7:    return "After 7 Days"
        case .d30:   return "After 30 Days"
        }
    }

    /// Idle time before archiving, or nil to disable.
    var interval: TimeInterval? {
        switch self {
        case .never: return nil
        case .h12:   return 12 * 3600
        case .d1:    return 24 * 3600
        case .d7:    return 7 * 24 * 3600
        case .d30:   return 30 * 24 * 3600
        }
    }

    private static let key = "muninn.autoArchive"
    static var current: AutoArchive {
        get { AutoArchive(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .d1 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// App-wide (non-profile) preferences.
enum AppSettings {
    static var warnBeforeQuitting: Bool {
        get { UserDefaults.standard.object(forKey: "muninn.warnBeforeQuitting") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "muninn.warnBeforeQuitting") }
    }
}
