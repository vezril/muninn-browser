import Foundation

/// JavaScript that powers page translation on the WebKit side. Text nodes are captured by *reference*
/// in `window.__mtr` (indexed), so reinjection and revert are O(1) by index and need no DOM markup.
/// State (`__mtrTranslated`) lives in the page, so it resets naturally on navigation.
enum PageTranslationScript {
    /// Collect translatable text nodes (main frame). Returns a JSON array of `{id, text}`.
    /// Skips script/style/code/editable/hidden nodes and anything without a letter.
    static let extract = #"""
    (function () {
      var SKIP = { SCRIPT:1, STYLE:1, NOSCRIPT:1, CODE:1, PRE:1, TEXTAREA:1, KBD:1, SAMP:1, TT:1 };
      window.__mtr = { nodes: [], orig: [] };
      var out = [];
      var walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
        acceptNode: function (n) {
          var t = n.nodeValue;
          if (!t) return NodeFilter.FILTER_REJECT;
          var s = t.trim();
          if (s.length < 2) return NodeFilter.FILTER_REJECT;
          if (!/\p{L}/u.test(s)) return NodeFilter.FILTER_REJECT;   // numbers/punctuation only
          var p = n.parentElement;
          if (!p) return NodeFilter.FILTER_REJECT;
          if (SKIP[p.tagName]) return NodeFilter.FILTER_REJECT;
          if (p.isContentEditable) return NodeFilter.FILTER_REJECT;
          if (p.closest('[translate="no"], .notranslate')) return NodeFilter.FILTER_REJECT;
          var cs;
          try { cs = getComputedStyle(p); } catch (e) { return NodeFilter.FILTER_ACCEPT; }
          if (cs && (cs.display === 'none' || cs.visibility === 'hidden')) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      var n, i = 0;
      while ((n = walker.nextNode())) {
        window.__mtr.nodes.push(n);
        window.__mtr.orig.push(n.nodeValue);
        out.push({ id: i, text: n.nodeValue });
        i++;
      }
      return JSON.stringify(out);
    })()
    """#

    /// Write translated strings back by index. `pairsJSON` is `[{id, t}]`. Returns count applied.
    static func reinject(pairsJSON: String) -> String {
        """
        (function (pairs) {
          var m = window.__mtr; if (!m) return 0;
          var c = 0;
          for (var k = 0; k < pairs.length; k++) {
            var node = m.nodes[pairs[k].id];
            if (node) { node.nodeValue = pairs[k].t; c++; }
          }
          window.__mtrTranslated = true;
          return c;
        })(\(pairsJSON))
        """
    }

    /// Restore original text; clears the translated flag.
    static let revert = """
    (function () {
      var m = window.__mtr; if (!m) return;
      for (var i = 0; i < m.nodes.length; i++) { if (m.nodes[i]) m.nodes[i].nodeValue = m.orig[i]; }
      window.__mtrTranslated = false;
    })()
    """

    /// Whether the active page is currently showing a translation.
    static let isTranslated = "!!window.__mtrTranslated"
}
