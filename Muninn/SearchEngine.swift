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
