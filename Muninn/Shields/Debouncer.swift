import Foundation

/// Bounce-tracking protection ("debouncing"): when a navigation targets a known bounce-tracker
/// that carries the real destination in a query parameter, recover the destination and skip the
/// tracker entirely. Pure + unit-tested.
enum Debouncer {
    struct Rule { let host: String; let pathPrefix: String?; let param: String }

    /// The real destination if `url` is a known bounce-tracker carrying it, else nil.
    static func destination(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              let rule = rules.first(where: { matches($0, host: host, path: url.path) }),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == rule.param })?.value, !raw.isEmpty
        else { return nil }
        // The value is usually the destination URL (possibly percent-encoded once → decoded here).
        guard let dest = URL(string: raw), let scheme = dest.scheme?.lowercased(),
              scheme == "http" || scheme == "https", dest.host != nil else { return nil }
        return dest
    }

    private static func matches(_ rule: Rule, host: String, path: String) -> Bool {
        let hostOK = host == rule.host || host.hasSuffix("." + rule.host)
        let pathOK = rule.pathPrefix.map { path.hasPrefix($0) } ?? true
        return hostOK && pathOK
    }

    /// Curated bounce-tracker redirect rules (host [+ path] → the param holding the destination).
    static let rules: [Rule] = [
        Rule(host: "l.facebook.com", pathPrefix: nil, param: "u"),
        Rule(host: "lm.facebook.com", pathPrefix: nil, param: "u"),
        Rule(host: "l.instagram.com", pathPrefix: nil, param: "u"),
        Rule(host: "l.messenger.com", pathPrefix: nil, param: "u"),
        Rule(host: "out.reddit.com", pathPrefix: nil, param: "url"),
        Rule(host: "t.umblr.com", pathPrefix: nil, param: "z"),
        Rule(host: "away.vk.com", pathPrefix: nil, param: "to"),
        Rule(host: "vk.com", pathPrefix: "/away.php", param: "to"),
        Rule(host: "steamcommunity.com", pathPrefix: "/linkfilter", param: "url"),
        Rule(host: "google.com", pathPrefix: "/url", param: "url"),
        Rule(host: "www.google.com", pathPrefix: "/url", param: "url"),
        Rule(host: "youtube.com", pathPrefix: "/redirect", param: "q"),
        Rule(host: "www.youtube.com", pathPrefix: "/redirect", param: "q"),
        Rule(host: "safelinks.protection.outlook.com", pathPrefix: nil, param: "url"),
        Rule(host: "click.redditmail.com", pathPrefix: nil, param: "url"),
        Rule(host: "linkedin.com", pathPrefix: "/redir", param: "url"),
        Rule(host: "www.linkedin.com", pathPrefix: "/redir", param: "url"),
        Rule(host: "href.li", pathPrefix: nil, param: "url"),
        Rule(host: "www.bing.com", pathPrefix: "/ck", param: "u"),
    ]
}
