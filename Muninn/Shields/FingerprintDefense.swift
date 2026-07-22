import Foundation

/// Fingerprint-defense ("farbling") — a MAIN-world script injected at document start that adds
/// tiny, per-page-load pseudo-random noise to the high-entropy fingerprinting surfaces (canvas
/// readback, WebGL unmasked vendor/renderer, Web Audio), so a page's device fingerprint differs
/// from the real one and across sessions, while staying imperceptible to normal use.
///
/// Limited by design to what JS can reach; it can't cover every surface a native engine (Brave)
/// randomizes, but it neutralises the classic canvas/WebGL/audio fingerprints.
enum FingerprintDefense {
    static let script = """
    (function () {
      try {
        // Exempt Proton (the shim/auth-fork path stays pristine).
        var host = location.hostname || '';
        if (host === 'proton.me' || host.slice(-11) === '.proton.me') return;

        // Per-page-load seed → deterministic within the page, different across loads/sites.
        var seed = (Math.random() * 4294967296) >>> 0;
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
            for (var i = 0; i < d.length; i += step) {
              d[i] = Math.min(255, Math.max(0, d[i] + ((rnd() * 3) | 0) - 1));
            }
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
        }

        // --- WebGL unmasked vendor / renderer (the big WebGL fingerprint) ---
        [window.WebGLRenderingContext, window.WebGL2RenderingContext].forEach(function (Ctor) {
          if (!Ctor || !Ctor.prototype.getParameter) return;
          var gp = Ctor.prototype.getParameter;
          Ctor.prototype.getParameter = function (p) {
            if (p === 37445) return 'Google Inc.';                 // UNMASKED_VENDOR_WEBGL
            if (p === 37446) return 'ANGLE (Generic Renderer)';    // UNMASKED_RENDERER_WEBGL
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
      } catch (e) {}
    })();
    """
}
