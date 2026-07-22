import Foundation

/// Removes known tracking query parameters (click identifiers, campaign tags) from a URL before
/// it's loaded — the params that let advertisers correlate you across sites, without touching
/// benign params. Pure + unit-tested.
enum QueryStripper {
    /// Returns a cleaned URL if any tracking params were removed, else nil (nothing to strip).
    static func strip(_ url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, !items.isEmpty else { return nil }
        let kept = items.filter { !isTracking($0.name.lowercased()) }
        guard kept.count != items.count else { return nil } // nothing removed
        comps.queryItems = kept.isEmpty ? nil : kept
        comps.percentEncodedQuery = comps.percentEncodedQuery // normalise
        return comps.url
    }

    static func isTracking(_ name: String) -> Bool {
        if exact.contains(name) { return true }
        return prefixes.contains { name.hasPrefix($0) }
    }

    /// Campaign / analytics prefixes (utm_source, utm_medium, hsa_*, oly_*, …).
    private static let prefixes: [String] = ["utm_", "hsa_", "oly_"]

    /// Known cross-site click identifiers and tracking tokens.
    private static let exact: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid",
        "ttclid", "igshid", "li_fat_id", "mc_eid", "mc_cid", "mkt_tok", "epik", "sc_cid",
        "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking",
        "vero_id", "vero_conv", "rb_clickid", "wickedid", "_openstat", "s_cid",
        "ml_subscriber", "ml_subscriber_hash", "spm", "scm", "cmpid", "campaign_id",
        "guccounter", "guce_referrer", "guce_referrer_sig",
    ]
}
