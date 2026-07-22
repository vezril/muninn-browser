import Foundation

/// Cleans a URL for **sharing** — removes the tracking/attribution params platforms append when you
/// copy or share a link (YouTube `si`, TikTok `_t`/`_r`, X `s`/`t`, Instagram `igsh`, …), on top of the
/// global cross-site click-IDs/UTM that `QueryStripper` already knows.
///
/// Rules are **host-scoped** where a param name is ambiguous, so meaningful params survive: YouTube's
/// `t` (timestamp) and `list` (playlist), Reddit's `context` (comment depth), Instagram's `img_index`
/// are all kept — only the share-attribution tokens are dropped. Pure + unit-tested. Curated from the
/// ClearURLs / AdGuard tracking catalogs for the platforms people actually share from.
enum ShareLinkCleaner {

    /// One platform's share-tracking rules. `hosts` match exactly or as a dot-suffix, so `m.youtube.com`
    /// and `music.youtube.com` inherit `youtube.com`; separate hosts (`youtu.be`) are listed explicitly.
    struct Rule {
        let hosts: [String]
        var params: Set<String> = []      // exact param names to drop (lowercased)
        var prefixes: [String] = []       // param-name prefixes to drop
        var stripPathRef = false          // Amazon-style: truncate the path at "/ref="
    }

    /// Returns the URL with share trackers removed (unchanged if there's nothing to strip).
    static func clean(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let host = (comps.host ?? "").lowercased()
        let rule = rules.first { r in r.hosts.contains { host == $0 || host.hasSuffix("." + $0) } }

        if let items = comps.queryItems, !items.isEmpty {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if QueryStripper.isTracking(name) { return false }          // global click-IDs / UTM
                guard let rule else { return true }
                if rule.params.contains(name) { return false }
                if rule.prefixes.contains(where: { name.hasPrefix($0) }) { return false }
                return true
            }
            comps.queryItems = kept.isEmpty ? nil : kept
        }

        // Amazon-style path: /dp/<ASIN>/ref=… → /dp/<ASIN>
        if rule?.stripPathRef == true, let r = comps.path.range(of: "/ref=") {
            comps.path = String(comps.path[..<r.lowerBound])
        }

        return comps.url ?? url
    }

    /// Per-platform share rules. Global click-IDs/UTM come from `QueryStripper`; these are the extra,
    /// host-specific share-attribution params. Add a platform = add one `Rule`.
    private static let rules: [Rule] = [
        // — video / music —
        Rule(hosts: ["youtube.com", "youtu.be", "youtube-nocookie.com"],
             params: ["si", "feature"]),                         // keep t, list, v, index, start
        Rule(hosts: ["open.spotify.com", "spotify.com"],
             params: ["si", "nd"]),
        Rule(hosts: ["twitch.tv"],
             params: ["tt_content", "tt_medium", "sr"]),
        Rule(hosts: ["bilibili.com"],
             params: ["spm_id_from", "vd_source", "share_source", "share_medium", "share_plat",
                      "share_tag", "unique_k", "from_source"]),
        // — social —
        Rule(hosts: ["twitter.com", "x.com"],
             params: ["s", "t", "ref_src", "ref_url", "cn", "refsrc"]),
        Rule(hosts: ["instagram.com"],
             params: ["igsh", "igshid"]),                        // keep img_index (carousel position)
        Rule(hosts: ["facebook.com", "fb.watch", "fb.me"],
             params: ["mibextid", "rdid", "share_url", "comment_tracking", "notif_t", "notif_id", "ref"],
             prefixes: ["__cft__", "__tn__"]),
        Rule(hosts: ["tiktok.com"],
             params: ["_r", "_t", "is_from_webapp", "sender_device", "web_id", "u_code", "preview_pb",
                      "share_app_id", "share_link_id", "share_item_id", "tt_from", "source",
                      "enter_method", "enter_from", "refer"]),
        Rule(hosts: ["reddit.com", "redd.it"],
             params: ["share_id", "ref", "ref_source", "correlation_id", "$deep_link", "$3p",
                      "_branch_match_id", "rdt"]),                // keep context
        Rule(hosts: ["linkedin.com"],
             params: ["trk", "trkinfo", "refid", "midtoken", "otptoken", "originalsubdomain"]),
        Rule(hosts: ["pinterest.com"],
             params: ["nic", "sender", "invite_code"], prefixes: ["nic_v"]),
        // — writing / news —
        Rule(hosts: ["substack.com"],
             params: ["r", "s"]),
        Rule(hosts: ["medium.com"],
             params: ["source"]),
        // — shopping —
        Rule(hosts: ["amazon.com", "amazon.co.uk", "amazon.ca", "amazon.de", "amazon.fr", "amazon.co.jp",
                     "amazon.in", "amazon.com.au", "amazon.it", "amazon.es", "amazon.com.br", "amazon.nl",
                     "amazon.com.mx"],
             params: ["ref", "ref_", "tag", "th", "psc", "smid", "qid", "sr", "dib", "dib_tag",
                      "content-id", "linkcode", "creativeasin", "ascsubtag", "crid", "sprefix",
                      "_encoding", "pldnsite", "pf_rd_p", "pf_rd_r"],
             prefixes: ["pd_rd_", "pf_rd_"], stripPathRef: true),
        Rule(hosts: ["ebay.com"],
             params: ["hash", "_trkparms", "_trksid", "mkevt", "mkcid", "mkrid", "campid", "toolid",
                      "customid"]),
        Rule(hosts: ["aliexpress.com"],
             prefixes: ["pdp_", "algo_", "aff_"]),
        // — search / platforms —
        Rule(hosts: ["google.com"],
             params: ["ved", "ei", "sa", "source", "sca_esv", "usg", "sourceid"], prefixes: ["gs_"]),
        Rule(hosts: ["steampowered.com", "steamcommunity.com"],
             params: ["snr", "curator_clanid"]),
    ]
}
