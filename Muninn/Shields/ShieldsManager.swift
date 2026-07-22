import WebKit

/// Brave-Shields-style privacy protections built on `WKContentRuleList`:
/// - block ads & trackers (bundled blocklist, third-party requests),
/// - upgrade http → https,
/// - block cross-site (third-party) cookies,
/// plus a per-site JavaScript toggle (applied via `WKWebpagePreferences`).
///
/// Global toggles + per-site "shields down" and "block scripts" persist in `UserDefaults`.
/// Changing anything recompiles the rule list; the host re-applies it to every tab.
@MainActor
final class ShieldsManager {
    static let shared = ShieldsManager()

    private(set) var ruleList: WKContentRuleList?
    /// Fired after a recompile so the host can re-apply the list to open tabs + refresh the icon.
    var onChange: (() -> Void)?

    // MARK: global settings

    var blockAds: Bool { get { d.object(forKey: kAds) as? Bool ?? true } set { d.set(newValue, forKey: kAds); rebuild() } }
    var upgradeHTTPS: Bool { get { d.object(forKey: kHTTPS) as? Bool ?? true } set { d.set(newValue, forKey: kHTTPS); rebuild() } }
    var blockCookies: Bool { get { d.object(forKey: kCookies) as? Bool ?? true } set { d.set(newValue, forKey: kCookies); rebuild() } }
    /// Strip tracking query params from navigations (not a content rule — applied in-flight).
    var stripQueryParams: Bool { get { d.object(forKey: kStrip) as? Bool ?? true } set { d.set(newValue, forKey: kStrip) } }
    /// Fingerprint defense (farbling) — injected MAIN-world script; read at tab creation.
    var fingerprintProtection: Bool { get { d.object(forKey: kFP) as? Bool ?? true } set { d.set(newValue, forKey: kFP) } }
    /// Bounce-tracking protection (debouncing) — applied in-flight in `decideNavigation`.
    var debounce: Bool { get { d.object(forKey: kDebounce) as? Bool ?? true } set { d.set(newValue, forKey: kDebounce) } }

    /// A random token generated once per app session (never persisted) — mixed with the site's
    /// eTLD+1 to seed farbling, so values are consistent within a session but differ across
    /// sites and across sessions (fingerprinting 2.0).
    let sessionToken = UUID().uuidString

    // MARK: per-site state

    /// Whether Shields are up (protecting) for a host.
    func shieldsUp(for host: String?) -> Bool {
        guard let key = siteKey(host) else { return true }
        return !shieldsDownList.contains(key)
    }
    func setShieldsUp(_ up: Bool, for host: String?) {
        guard let key = siteKey(host) else { return }
        var list = shieldsDownList
        if up { list.remove(key) } else { list.insert(key) }
        shieldsDownList = list
        rebuild() // exemptions change the rule list
    }

    func scriptsBlocked(for host: String?) -> Bool {
        guard let key = siteKey(host) else { return false }
        return scriptsList.contains(key)
    }
    func setScriptsBlocked(_ blocked: Bool, for host: String?) {
        guard let key = siteKey(host) else { return }
        var list = scriptsList
        if blocked { list.insert(key) } else { list.remove(key) }
        scriptsList = list
        onChange?() // no recompile needed (JS is a webpage-preference)
    }

    /// Whether JavaScript should be allowed for a navigation (Shields down → always allowed).
    func javaScriptAllowed(for url: URL?) -> Bool {
        guard shieldsUp(for: url?.host) else { return true }
        return !scriptsBlocked(for: url?.host)
    }

    // MARK: compilation

    /// (Re)compile the content-rule list from current settings and notify on completion.
    func rebuild() {
        guard let json = buildRules(), let store = WKContentRuleListStore.default() else {
            ruleList = nil; onChange?(); return
        }
        store.compileContentRuleList(forIdentifier: "muninn-shields", encodedContentRuleList: json) { [weak self] list, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let list { self.ruleList = list }
                self.onChange?()
            }
        }
    }

    /// The encoded rule list, or nil if there's nothing to enforce.
    private func buildRules() -> String? {
        var rules: [[String: Any]] = []
        if blockAds {
            for domain in Self.blocklist {
                let esc = domain.replacingOccurrences(of: ".", with: "\\.")
                rules.append([
                    "trigger": ["url-filter": "^https?://([^/]+\\.)?\(esc)", "load-type": ["third-party"]],
                    "action": ["type": "block"],
                ])
            }
        }
        if upgradeHTTPS {
            rules.append(["trigger": ["url-filter": "^http://"], "action": ["type": "make-https"]])
        }
        if blockCookies {
            rules.append(["trigger": ["url-filter": ".*", "load-type": ["third-party"]], "action": ["type": "block-cookies"]])
        }
        guard !rules.isEmpty else { return nil }
        // Shields-down sites: ignore everything above for those documents (must be LAST).
        let down = Array(shieldsDownList).map { "*\($0)" }
        if !down.isEmpty {
            rules.append(["trigger": ["url-filter": ".*", "if-domain": down], "action": ["type": "ignore-previous-rules"]])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    // MARK: storage

    private let d = UserDefaults.standard
    private let kAds = "muninn.shields.ads", kHTTPS = "muninn.shields.https", kCookies = "muninn.shields.cookies"
    private let kStrip = "muninn.shields.strip", kFP = "muninn.shields.fp", kDebounce = "muninn.shields.debounce"
    private let kDown = "muninn.shields.down", kScripts = "muninn.shields.scripts"

    private var shieldsDownList: Set<String> {
        get { Set(d.stringArray(forKey: kDown) ?? []) }
        set { d.set(Array(newValue), forKey: kDown) }
    }
    private var scriptsList: Set<String> {
        get { Set(d.stringArray(forKey: kScripts) ?? []) }
        set { d.set(Array(newValue), forKey: kScripts) }
    }

    /// Registrable-ish site key: host without a leading "www.".
    func siteKey(_ host: String?) -> String? {
        guard var h = host?.lowercased(), !h.isEmpty else { return nil }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        return h
    }

    // A compact curated blocklist of common ad/tracker hosts (EasyList import is a future step).
    static let blocklist: [String] = [
        "doubleclick.net", "googlesyndication.com", "googletagservices.com", "googletagmanager.com",
        "google-analytics.com", "googleadservices.com", "adservice.google.com", "pagead2.googlesyndication.com",
        "analytics.google.com", "connect.facebook.net", "graph.facebook.com", "ads.facebook.com",
        "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "adform.net", "adroll.com", "adcolony.com",
        "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "scorecardresearch.com", "quantserve.com",
        "quantcast.com", "moatads.com", "doubleverify.com", "adsafeprotected.com", "pubmatic.com",
        "rubiconproject.com", "openx.net", "casalemedia.com", "33across.com", "bidswitch.net", "sharethrough.com",
        "smartadserver.com", "gumgum.com", "indexww.com", "yieldmo.com", "teads.tv", "spotxchange.com",
        "spotx.tv", "contextweb.com", "districtm.io", "lijit.com", "sonobi.com", "media.net", "adtelligent.com",
        "hotjar.com", "mouseflow.com", "fullstory.com", "mixpanel.com", "segment.com", "segment.io",
        "amplitude.com", "heap.io", "heapanalytics.com", "chartbeat.com", "chartbeat.net", "newrelic.com",
        "nr-data.net", "bugsnag.com", "sentry.io", "branch.io", "appsflyer.com", "adjust.com", "kochava.com",
        "bluekai.com", "krxd.net", "demdex.net", "everesttech.net", "rlcdn.com", "crwdcntrl.net", "agkn.com",
        "mathtag.com", "tapad.com", "id5-sync.com", "yieldlab.net", "onetag.com", "3lift.com", "gemius.pl",
        "hs-analytics.net", "hsubspot.com", "hubspot.com", "marketo.net", "pardot.com", "cdn.mxpnl.com",
        "clarity.ms", "bat.bing.com", "ads.linkedin.com", "px.ads.linkedin.com", "analytics.tiktok.com",
        "ads.pinterest.com", "ct.pinterest.com", "cdn.taboola.com", "trc.taboola.com", "log.outbrain.com",
        "ads.yahoo.com", "analytics.yahoo.com", "advertising.com", "adtech.com", "yieldoptimizer.com",
        "serving-sys.com", "flashtalking.com", "turn.com", "w55c.net", "simpli.fi", "stickyadstv.com",
        "zemanta.com", "revcontent.com", "mgid.com", "adblade.com", "propellerads.com", "popads.net",
        "onclickads.net", "exoclick.com", "trafficjunky.net", "juicyads.com", "smartlook.com", "inspectlet.com",
        "loggly.com", "optimizely.com", "crazyegg.com", "vwo.com", "yandex.ru", "mc.yandex.ru", "metrika.yandex.ru",
    ]
}
