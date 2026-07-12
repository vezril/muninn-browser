// background-worker-boot.js — the first script the background-host Worker runs.
// Order: capture console/errors -> load polyfill -> await init -> load background.js.
// Everything is forwarded to the host page, which relays to native for the S1
// boot audit (FR-7 / background-host spec).
(function () {
  "use strict";

  function forward(kind, payload) {
    try { self.postMessage(Object.assign({ __shim: kind }, payload)); } catch (_) {}
  }

  // Console capture. Ground rule 1 / NFR-8: background.js is unmodified
  // third-party code that may log vault data. Only warn/error carry text (the
  // S1 clean-boot signal is unhandled exceptions / missing-API TypeErrors,
  // which are error-level); log/info/debug forward LENGTH ONLY, never content.
  ["log", "info", "warn", "error", "debug"].forEach(function (level) {
    var orig = self.console && self.console[level];
    var keepsText = (level === "warn" || level === "error");
    self.console[level] = function () {
      if (keepsText) {
        var parts = [];
        for (var i = 0; i < arguments.length; i++) {
          var a = arguments[i];
          try { parts.push(typeof a === "string" ? a : JSON.stringify(a)); }
          catch (_) { parts.push(String(a)); }
        }
        forward("console", { level: level, text: parts.join(" ") });
      } else {
        var len = 0;
        for (var j = 0; j < arguments.length; j++) { try { len += String(arguments[j]).length; } catch (_) {} }
        forward("console", { level: level, len: len }); // no content
      }
      if (orig) try { orig.apply(self.console, arguments); } catch (_) {}
    };
  });

  // Test-only signal channel (Muninn-injected scenarios), kept separate from
  // Proton's console so test markers never depend on console text capture.
  self.__report = function (name, ok, value) { forward("scenario", { name: name, ok: !!ok, value: value }); };

  self.addEventListener("error", function (e) {
    forward("workerError", { message: e.message, filename: e.filename, lineno: e.lineno, colno: e.colno });
  });
  self.addEventListener("unhandledrejection", function (e) {
    var r = e && e.reason;
    forward("workerRejection", { message: (r && (r.message || String(r))) || "unhandledrejection" });
  });

  importScripts("shim-polyfill.js"); // defines self.__shimInit + inbound listener

  // Diagnostic-only: run a scenario snippet in the worker (browser.* is live).
  self.addEventListener("message", function (e) {
    if (!e.data || e.data.__shim !== "eval") return;
    try { (0, eval)(e.data.code); }
    catch (err) { forward("console", { level: "error", text: "eval: " + (err && err.message || String(err)) }); }
  });

  self.addEventListener("message", function onInit(e) {
    if (!e.data || e.data.__shim !== "init") return;
    self.removeEventListener("message", onInit);
    try {
      self.__shimInit(e.data); // sets self.chrome / self.browser, posts "ready"
      importScripts("background.js"); // Proton's real service worker, now safe
      forward("bgLoaded", {});
    } catch (err) {
      forward("workerError", { message: "background.js load threw: " + (err && err.message || String(err)) });
    }
  });

  forward("bootReady", {}); // ask the page for init data
})();
