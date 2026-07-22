import Foundation

/// Cosmetic ad hiding (part of Shields "block ads & trackers"). Network-level blocking stops the ad
/// from loading, but the page often leaves the empty slot behind — a blank white bar (e.g. AdThrive's
/// sticky footer). This injects a small stylesheet that hides common ad-slot containers so no empty
/// space remains. CSS handles dynamically-inserted slots automatically (no observer needed).
/// `*.proton.me` is exempt (keeps the shim path pristine).
enum AdCosmetics {
    static func script() -> String {
        // Curated, ad-specific selectors only (safe to hide):
        //  - `.adthrive-ad` is on every AdThrive/Raptive ad slot (footer/header/sidebar/content).
        //  - Google Ad Manager / AdSense slot containers.
        let css = """
        .adthrive-ad, .adthrive-sticky-outstream, .adthrive-collapse-mobile-background,
        .adthrive-footer-message,
        ins.adsbygoogle, .adsbygoogle, .google-auto-placed,
        [id^="div-gpt-ad"], [id^="google_ads_iframe"], [id^="AdThrive_"]
        { display: none !important; }
        """
        return """
        (function () {
          try {
            var h = location.hostname; if (h === "proton.me" || h.slice(-11) === ".proton.me") return;
            var s = document.createElement("style");
            s.textContent = \(jsString(css));
            (document.head || document.documentElement).appendChild(s);
          } catch (e) {}
        })();
        """
    }

    /// JSON-encode a string into a safe JS string literal.
    private static func jsString(_ s: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [s]), encoding: .utf8))
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
}
