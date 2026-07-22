import Foundation

/// Cookie-consent notice blocking (Shields). Privacy-preserving: it clicks the **reject / necessary-
/// only** button of known consent-management platforms (OneTrust, Cookiebot, Didomi, Usercentrics,
/// Quantcast, TrustArc, Osano, Complianz, Sourcepoint, …) and cosmetically hides the banner +
/// unlocks page scrolling. It NEVER clicks "accept all" — no interaction means no consent, so sites
/// fall back to essential-only cookies. MAIN world, document-start, all frames; a debounced
/// MutationObserver catches late-injected banners for the first few seconds.
enum CookieConsent {
    static func script() -> String {
        """
        (function () {
          "use strict";
          // Exempt *.proton.me — keep the shim / auth-fork path pristine.
          try { var h = location.hostname; if (h === "proton.me" || h.slice(-11) === ".proton.me") return; } catch (e) {}
          // Reject / "necessary only" buttons of common consent platforms (specific selectors only).
          var REJECT = [
            ".adthrive-act25-btn.secondary", ".adthrive-us-cmp-modal-decline",
            "#adthrive-ccpa-modal-cancel-btn",
            "#onetrust-reject-all-handler",
            "#CybotCookiebotDialogBodyButtonDecline",
            "#CybotCookiebotDialogBodyLevelButtonLevelOptinDeclineAll",
            ".cc-btn.cc-deny", "a.cc-deny", "button.cc-deny",
            "#didomi-notice-disagree-button", ".didomi-continue-without-agreeing",
            "button[data-testid='uc-deny-all-button']",
            ".qc-cmp2-summary-buttons button[mode='secondary']",
            ".osano-cm-denyAll", ".cmplz-deny",
            "button.sp_choice_type_REJECT_ALL", "button[title='Reject All']",
            "button[aria-label='Reject all']", "button[aria-label='Decline']",
            "#truste-consent-required"
          ];
          // Banner containers to cosmetically hide (curated CMP roots + moderately generic ids).
          var HIDE = [
            ".adthrive-act25-overlay", ".adthrive-act25-modal",
            ".adthrive-us-cmp-modal", ".adthrive-ccpa-modal",
            "#onetrust-banner-sdk", "#onetrust-consent-sdk", ".onetrust-pc-dark-filter",
            "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay",
            ".cc-window", ".cc-banner",
            "#didomi-host", ".didomi-popup-container", ".didomi-notice-banner",
            "#usercentrics-root", "#uc-banner-modal", ".uc-banner",
            ".qc-cmp2-container", ".qc-cmp-cleanslate",
            "#truste-consent-track", ".truste_overlay", ".truste_box_overlay",
            ".osano-cm-window", ".cmplz-cookiebanner",
            "#cookie-law-info-bar", "#cookie-notice", ".cookie-notice-container",
            "[id^='sp_message_container']",
            "[id*='cookie-banner']", "[class*='cookie-banner']",
            "[id*='cookie-consent']", "[class*='cookie-consent']"
          ];
          var LOCK_CLASSES = ["modal-open", "no-scroll", "noscroll", "overflow-hidden",
                              "cookie-modal-open", "has-cookie-banner", "gdpr-open"];
          function clickReject() {
            for (var i = 0; i < REJECT.length; i++) {
              try {
                var el = document.querySelector(REJECT[i]);
                if (el && el.offsetParent !== null) { el.click(); return true; }
              } catch (e) {}
            }
            return false;
          }
          // Strong "reject/necessary-only" phrases (EN + FR) — catches CMPs (incl. iframe ad
          // CMPs like AdThrive/Raptive) whose selectors we don't hardcode, in any language.
          var REJECT_TEXT = [
            "reject all", "reject", "decline all", "decline", "deny all", "deny", "refuse all",
            "do not consent", "continue without accepting", "necessary only", "only necessary",
            "use necessary cookies only", "essential only", "manage rejections", "i decline",
            "tout refuser", "refuser tout", "refuser", "tout rejeter", "rejeter",
            "continuer sans accepter", "sans accepter", "nécessaires uniquement",
            "uniquement les nécessaires", "essentiels uniquement", "ne pas accepter",
            "je refuse", "poursuivre sans accepter"
          ];
          function clickRejectByText() {
            // Only within a consent context (this frame/page must mention cookies/consent),
            // so we never click an unrelated "decline" elsewhere.
            try {
              var ctx = ((document.body && document.body.innerText) || "").slice(0, 4000).toLowerCase();
              if (!/cookie|consent|privacy|témoin|confidentialit|gdpr|rgpd|loi 25|renseignements personnels/.test(ctx)) return false;
            } catch (e) { return false; }
            var btns = document.querySelectorAll("button, a[role='button'], [role='button'], input[type='button'], input[type='submit']");
            for (var i = 0; i < btns.length; i++) {
              var b = btns[i];
              if (b.offsetParent === null) continue;
              var txt = ((b.innerText || b.value || b.getAttribute("aria-label") || "").trim()).toLowerCase();
              if (!txt || txt.length > 45) continue;
              for (var j = 0; j < REJECT_TEXT.length; j++) {
                // `contains` (not prefix) so bilingual labels like "Déclin/Decline" match.
                if (txt.indexOf(REJECT_TEXT[j]) >= 0) { try { b.click(); return true; } catch (e) {} }
              }
            }
            return false;
          }
          function hide() {
            for (var i = 0; i < HIDE.length; i++) {
              try {
                var list = document.querySelectorAll(HIDE[i]);
                for (var j = 0; j < list.length; j++) list[j].style.setProperty("display", "none", "important");
              } catch (e) {}
            }
          }
          function unlock() {
            try {
              [document.documentElement, document.body].forEach(function (el) {
                if (!el) return;
                if (el.style && el.style.overflow) el.style.removeProperty("overflow");
                if (el.classList) LOCK_CLASSES.forEach(function (c) { el.classList.remove(c); });
              });
            } catch (e) {}
          }
          // Hide consent CMPs that render inside a (cross-origin) iframe — the parent can hide the
          // iframe even though it can't reach its content (e.g. AdThrive/Raptive, Sourcepoint).
          function hideFrames() {
            try {
              var f = document.querySelectorAll(
                "iframe[id*='mcmp' i], iframe[src*='/rnf.html'], iframe[id^='sp_message_iframe'], " +
                "iframe[title*='consent' i], iframe[title*='cookie' i], iframe[src*='consensu.org'], " +
                "iframe[src*='cmp.'], iframe[src*='/cmp/']");
              for (var i = 0; i < f.length; i++) {
                var el = f[i];
                el.style.setProperty("display", "none", "important");
                var p = el.parentElement, depth = 0;
                while (p && depth < 3) {
                  var cs = getComputedStyle(p);
                  if (cs.position === "fixed" || parseInt(cs.zIndex || 0, 10) >= 1000) {
                    p.style.setProperty("display", "none", "important"); break;
                  }
                  p = p.parentElement; depth++;
                }
              }
            } catch (e) {}
          }
          function run() { if (!clickReject()) clickRejectByText(); hide(); hideFrames(); unlock(); }
          run();
          document.addEventListener("DOMContentLoaded", run);
          // Catch late/async banners for a few seconds, debounced, then stop (perf).
          try {
            var pending = null;
            var obs = new MutationObserver(function () {
              if (pending) return;
              pending = setTimeout(function () { pending = null; run(); }, 300);
            });
            // Watch childList AND class/style changes — many CMPs keep the modal in the DOM and
            // just toggle a `.show` class (an attribute change, not a new node).
            obs.observe(document.documentElement || document,
                        { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "style"] });
            setTimeout(function () { try { obs.disconnect(); } catch (e) {} }, 20000);
          } catch (e) {}
        })();
        """
    }
}
