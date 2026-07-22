import Foundation

/// Built-in JSON viewer (Firefox-style): when the top document is JSON, replace the raw text with a
/// prettified, syntax-coloured, collapsible tree plus a toolbar (Pretty/Raw, Expand/Collapse all, Copy).
/// Injected MAIN-world at document-end; it self-gates on `document.contentType` / a `.json` URL and a
/// successful `JSON.parse`, so it never disturbs HTML pages. Very large files fall back to a prettified,
/// highlighted `<pre>` to stay responsive. Theme-aware via `prefers-color-scheme`.
enum JSONViewer {
    static let script = #"""
    (function () {
      function run() {
        if (window.__muninnJSON) return;
        var raw, data;
        try {
          if (window.top !== window.self) return;                    // top document only
          var ct = (document.contentType || '').toLowerCase();
          var path = (location.pathname || '');
          var isType = ct === 'application/json' || ct === 'text/json' ||
                       ct.indexOf('application/json') === 0 || /\+json$/.test(ct);
          var isURL = /\.json([?#]|$)/i.test(path);
          if (!isType && !isURL) return;
          raw = (document.body ? document.body.textContent : '') || '';
          if (!raw.trim()) return;                                    // body text not ready yet
          try { data = JSON.parse(raw); } catch (e) { return; }       // not valid JSON → leave raw
        } catch (e) { return; }

        window.__muninnJSON = true;
        try { build(data, raw); }
        catch (e) {                                                   // never leave a blank page
          try { document.body.innerHTML = ''; document.body.appendChild(document.createTextNode(raw)); } catch (_) {}
        }
      }

      function el(tag, cls) { var e = document.createElement(tag); if (cls) e.className = cls; return e; }
      function punct(t) { var s = el('span', 'mj-punct'); s.textContent = t; return s; }
      function keySpan(k) { var s = el('span', 'mj-key'); s.textContent = JSON.stringify(String(k)); return s; }
      function valueSpan(v) {
        if (v === null) { var n = el('span', 'mj-null'); n.textContent = 'null'; return n; }
        var t = typeof v;
        if (t === 'string') {
          if (/^https?:\/\/[^\s"]+$/.test(v)) {
            var a = el('a', 'mj-str mj-link'); a.href = v; a.target = '_blank'; a.rel = 'noopener';
            a.textContent = JSON.stringify(v); return a;
          }
          var s = el('span', 'mj-str'); s.textContent = JSON.stringify(v); return s;
        }
        if (t === 'number') { var num = el('span', 'mj-num'); num.textContent = String(v); return num; }
        if (t === 'boolean') { var b = el('span', 'mj-bool'); b.textContent = String(v); return b; }
        var o = el('span'); o.textContent = String(v); return o;
      }

      var setters = [];   // collapse setters, for Expand/Collapse all

      function renderNode(key, value, parent, isLast) {
        if (value !== null && typeof value === 'object') { renderContainer(key, value, parent, isLast); return; }
        var line = el('div', 'mj-row');
        line.appendChild(el('span', 'mj-gutter'));
        if (key !== null) { line.appendChild(keySpan(key)); line.appendChild(punct(': ')); }
        line.appendChild(valueSpan(value));
        if (!isLast) line.appendChild(punct(','));
        parent.appendChild(line);
      }

      function renderContainer(key, value, parent, isLast) {
        var isArr = Array.isArray(value);
        var keys = isArr ? null : Object.keys(value);
        var count = isArr ? value.length : keys.length;

        if (count === 0) {                                            // empty {} / [] on one line
          var e = el('div', 'mj-row'); e.appendChild(el('span', 'mj-gutter'));
          if (key !== null) { e.appendChild(keySpan(key)); e.appendChild(punct(': ')); }
          e.appendChild(punct(isArr ? '[]' : '{}'));
          if (!isLast) e.appendChild(punct(','));
          parent.appendChild(e); return;
        }

        var wrap = el('div', 'mj-node');
        var head = el('div', 'mj-row mj-head');
        var tog = el('span', 'mj-toggle'); tog.textContent = '▾';  // ▾
        head.appendChild(tog);
        if (key !== null) { head.appendChild(keySpan(key)); head.appendChild(punct(': ')); }
        head.appendChild(punct(isArr ? '[' : '{'));
        var ell = el('span', 'mj-ellipsis'); ell.textContent = ' … '; head.appendChild(ell);
        var inl = el('span', 'mj-inline'); inl.textContent = (isArr ? ']' : '}') + (isLast ? '' : ','); head.appendChild(inl);
        var meta = el('span', 'mj-meta');
        meta.textContent = '  ' + count + (isArr ? (count === 1 ? ' item' : ' items') : (count === 1 ? ' key' : ' keys'));
        head.appendChild(meta);
        wrap.appendChild(head);

        var kids = el('div', 'mj-children');
        if (isArr) { for (var i = 0; i < count; i++) renderNode(null, value[i], kids, i === count - 1); }
        else { for (var j = 0; j < count; j++) renderNode(keys[j], value[keys[j]], kids, j === count - 1); }
        wrap.appendChild(kids);

        var foot = el('div', 'mj-row mj-foot');
        foot.appendChild(el('span', 'mj-gutter'));
        foot.appendChild(punct((isArr ? ']' : '}') + (isLast ? '' : ',')));
        wrap.appendChild(foot);
        parent.appendChild(wrap);

        var collapsed = false;
        function set(c) { collapsed = c; wrap.classList.toggle('mj-collapsed', c); tog.textContent = c ? '▸' : '▾'; } // ▸ ▾
        head.addEventListener('click', function () {
          var sel = window.getSelection && String(window.getSelection());
          if (sel) return;                                           // don't collapse while selecting text
          set(!collapsed);
        });
        setters.push(set);
      }

      function highlightBig(pretty) {                                // regex highlight for the <pre> fallback
        var esc = pretty.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        return esc.replace(/("(\\u[a-fA-F0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false)\b|\bnull\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,
          function (m) {
            var cls = 'mj-num';
            if (/^"/.test(m)) cls = /:$/.test(m) ? 'mj-key' : 'mj-str';
            else if (/true|false/.test(m)) cls = 'mj-bool';
            else if (/null/.test(m)) cls = 'mj-null';
            return '<span class="' + cls + '">' + m + '</span>';
          });
      }

      function build(data, raw) {
        var style = el('style'); style.textContent = CSS; document.head.appendChild(style);
        document.body.innerHTML = ''; document.body.className = 'mj-body';

        var bar = el('div', 'mj-toolbar');
        var title = el('span', 'mj-title'); title.textContent = 'JSON'; bar.appendChild(title);
        function btn(label) { var b = el('button', 'mj-btn'); b.textContent = label; bar.appendChild(b); return b; }

        var content = el('div', 'mj-content');
        var rawPre = el('pre', 'mj-raw'); rawPre.textContent = raw; rawPre.style.display = 'none';

        var big = raw.length > 3000000;                              // ~3MB: skip interactive tree
        var tree;
        if (big) {
          tree = el('pre', 'mj-content mj-prebig');
          tree.innerHTML = highlightBig(JSON.stringify(data, null, 2));
        } else {
          tree = el('div', 'mj-tree');
          renderNode(null, data, tree, true);
        }
        content.appendChild(tree); content.appendChild(rawPre);

        var showingRaw = false;
        var rawBtn = btn('Raw');
        var expandBtn = big ? null : btn('Expand all');
        var collapseBtn = big ? null : btn('Collapse all');
        var copyBtn = btn('Copy');

        rawBtn.addEventListener('click', function () {
          showingRaw = !showingRaw;
          tree.style.display = showingRaw ? 'none' : '';
          rawPre.style.display = showingRaw ? '' : 'none';
          rawBtn.textContent = showingRaw ? 'Pretty' : 'Raw';
          if (expandBtn) expandBtn.disabled = showingRaw;
          if (collapseBtn) collapseBtn.disabled = showingRaw;
        });
        if (expandBtn) expandBtn.addEventListener('click', function () { setters.forEach(function (s) { s(false); }); });
        if (collapseBtn) collapseBtn.addEventListener('click', function () { setters.forEach(function (s) { s(true); }); });
        copyBtn.addEventListener('click', function () {
          try {
            navigator.clipboard.writeText(JSON.stringify(data, null, 2));
            var o = copyBtn.textContent; copyBtn.textContent = 'Copied!';
            setTimeout(function () { copyBtn.textContent = o; }, 1200);
          } catch (e) {}
        });

        document.body.appendChild(bar);
        document.body.appendChild(content);
      }

      var CSS = [
        ':root{--mj-bg:#fff;--mj-fg:#1f2328;--mj-key:#0451a5;--mj-str:#0a7d33;--mj-num:#098658;',
        '--mj-bool:#0b57d0;--mj-null:#7a3e9d;--mj-punct:#8a9099;--mj-line:#e6e8eb;--mj-tb:#f6f8fa;--mj-btn:#eaecef;}',
        '@media (prefers-color-scheme:dark){:root{--mj-bg:#1e1e1e;--mj-fg:#d4d4d4;--mj-key:#9cdcfe;',
        '--mj-str:#ce9178;--mj-num:#b5cea8;--mj-bool:#569cd6;--mj-null:#c586c0;--mj-punct:#808080;',
        '--mj-line:#333;--mj-tb:#252526;--mj-btn:#333a41;}}',
        '.mj-body{margin:0;background:var(--mj-bg);color:var(--mj-fg);',
        'font:13px/1.55 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;}',
        '.mj-toolbar{position:sticky;top:0;display:flex;gap:6px;align-items:center;padding:8px 12px;',
        'background:var(--mj-tb);border-bottom:1px solid var(--mj-line);z-index:10;}',
        '.mj-title{font-weight:600;margin-right:8px;opacity:.75;}',
        '.mj-btn{font:inherit;font-size:12px;padding:3px 10px;border:1px solid var(--mj-line);',
        'background:var(--mj-btn);color:var(--mj-fg);border-radius:6px;cursor:pointer;}',
        '.mj-btn:hover{filter:brightness(1.08);}.mj-btn:disabled{opacity:.4;cursor:default;}',
        '.mj-content{padding:12px 16px;}',
        '.mj-row{white-space:pre-wrap;word-break:break-word;}',
        '.mj-head{cursor:pointer;border-radius:4px;}.mj-head:hover{background:rgba(127,127,127,.10);}',
        '.mj-children{padding-left:1.35em;border-left:1px solid var(--mj-line);margin-left:.35em;}',
        '.mj-toggle,.mj-gutter{display:inline-block;width:1.1em;color:var(--mj-punct);user-select:none;text-align:center;}',
        '.mj-key{color:var(--mj-key);}.mj-str{color:var(--mj-str);}.mj-num{color:var(--mj-num);}',
        '.mj-bool{color:var(--mj-bool);}.mj-null{color:var(--mj-null);}.mj-punct{color:var(--mj-punct);}',
        '.mj-meta{color:var(--mj-punct);font-style:italic;opacity:.8;}.mj-ellipsis{color:var(--mj-punct);}',
        '.mj-link{color:var(--mj-str);text-decoration:underline;}',
        '.mj-head>.mj-ellipsis,.mj-head>.mj-inline,.mj-head>.mj-meta{display:none;}',
        '.mj-collapsed>.mj-head>.mj-ellipsis,.mj-collapsed>.mj-head>.mj-inline,',
        '.mj-collapsed>.mj-head>.mj-meta{display:inline;}',
        '.mj-collapsed>.mj-children,.mj-collapsed>.mj-foot{display:none;}',
        '.mj-raw{padding:12px 16px;white-space:pre-wrap;word-break:break-word;margin:0;}',
        '.mj-prebig{white-space:pre-wrap;word-break:break-word;}'
      ].join('');

      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run);
      run();
      window.addEventListener('load', run);                          // retry if body text arrived late
    })();
    """#
}
