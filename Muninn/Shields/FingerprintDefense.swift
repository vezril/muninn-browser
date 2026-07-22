import Foundation

/// Fingerprint-defense ("farbling") 2.0 — a MAIN-world script injected at document start that adds
/// tiny, deterministic noise to the high-entropy fingerprinting surfaces.
///
/// The seed is `hash(sessionToken + eTLD+1)`: values are **consistent within a session for a site**
/// (so pages work), but **differ across sites and across sessions** (so a fingerprint can't be
/// correlated). Covers canvas, WebGL, Web Audio, `measureText`, `hardwareConcurrency`, and reduces
/// language entropy (`navigator.languages` → primary only). `*.proton.me` is exempt.
enum FingerprintDefense {
    static func script(sessionToken: String) -> String {
        """
        (function () {
          try {
            var host = location.hostname || '';
            if (host === 'proton.me' || host.slice(-11) === '.proton.me') return;

            // Per-session, per-site seed (fingerprinting 2.0).
            var TOKEN = "\(sessionToken)";
            function etld1(h) { var p = h.split('.'); return p.length <= 2 ? h : p.slice(-2).join('.'); }
            function hash(s) { var h = 0xdeadbeef; for (var i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 2654435761); return (h >>> 0) || 1; }
            var seed = hash(TOKEN + '|' + etld1(host));
            function rnd() {
              seed = (seed + 0x6D2B79F5) | 0;
              var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
              t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
              return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            }

            // --- Canvas 2D readback ---
            var C2D = window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype;
            if (C2D && C2D.getImageData) {
              var gid = C2D.getImageData;
              C2D.getImageData = function () {
                var img = gid.apply(this, arguments);
                var d = img.data, step = Math.max(4, ((d.length / 256) | 0) * 4);
                for (var i = 0; i < d.length; i += step) { d[i] = Math.min(255, Math.max(0, d[i] + ((rnd() * 3) | 0) - 1)); }
                return img;
              };
            }
            var CV = window.HTMLCanvasElement && HTMLCanvasElement.prototype;
            if (CV) {
              ['toDataURL', 'toBlob'].forEach(function (m) {
                if (!CV[m]) return;
                var orig = CV[m];
                CV[m] = function () {
                  try {
                    var ctx = this.getContext('2d');
                    if (ctx && this.width && this.height) {
                      ctx.fillStyle = 'rgba(' + ((rnd() * 255) | 0) + ',0,0,0.003)';
                      ctx.fillRect((rnd() * this.width) | 0, (rnd() * this.height) | 0, 1, 1);
                    }
                  } catch (e) {}
                  return orig.apply(this, arguments);
                };
              });
              // measureText — perturb width by a fixed per-page epsilon.
              if (C2D && C2D.measureText) {
                var mt = C2D.measureText, eps = (rnd() - 0.5) * 0.02;
                C2D.measureText = function () {
                  var m = mt.apply(this, arguments);
                  try { var w = m.width; Object.defineProperty(m, 'width', { get: function () { return w + eps; }, configurable: true }); } catch (e) {}
                  return m;
                };
              }
            }

            // --- WebGL unmasked vendor / renderer ---
            [window.WebGLRenderingContext, window.WebGL2RenderingContext].forEach(function (Ctor) {
              if (!Ctor || !Ctor.prototype.getParameter) return;
              var gp = Ctor.prototype.getParameter;
              Ctor.prototype.getParameter = function (p) {
                if (p === 37445) return 'Google Inc.';
                if (p === 37446) return 'ANGLE (Generic Renderer)';
                return gp.apply(this, arguments);
              };
            });

            // --- Web Audio ---
            if (window.AudioBuffer && AudioBuffer.prototype.getChannelData) {
              var gcd = AudioBuffer.prototype.getChannelData;
              AudioBuffer.prototype.getChannelData = function () {
                var a = gcd.apply(this, arguments);
                for (var i = 0; i < a.length; i += 1000) { a[i] = a[i] + (rnd() * 2 - 1) * 1e-7; }
                return a;
              };
            }
            if (window.AnalyserNode && AnalyserNode.prototype.getFloatFrequencyData) {
              var gffd = AnalyserNode.prototype.getFloatFrequencyData;
              AnalyserNode.prototype.getFloatFrequencyData = function (arr) {
                gffd.apply(this, arguments);
                for (var i = 0; i < arr.length; i += 25) { arr[i] = arr[i] + (rnd() * 2 - 1) * 0.1; }
              };
            }

            // --- Navigator: standardize hardwareConcurrency + reduce language entropy ---
            try {
              var cores = [4, 8][(rnd() * 2) | 0];
              Object.defineProperty(navigator, 'hardwareConcurrency', { get: function () { return cores; }, configurable: true });
            } catch (e) {}
            try {
              Object.defineProperty(navigator, 'languages', { get: function () { return [navigator.language]; }, configurable: true });
            } catch (e) {}
          } catch (e) {}
        })();
        """
    }
}
