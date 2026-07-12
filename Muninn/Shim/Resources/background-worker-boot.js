// background-worker-boot.js — the first script the background-host Worker runs.
// Order: capture console/errors -> load polyfill -> await init -> load background.js.
// Everything is forwarded to the host page, which relays to native for the S1
// boot audit (FR-7 / background-host spec).
(function () {
  "use strict";

  function forward(kind, payload) {
    try { self.postMessage(Object.assign({ __shim: kind }, payload)); } catch (_) {}
  }

  // Console capture — a Worker's console is not visible to native otherwise.
  ["log", "info", "warn", "error", "debug"].forEach(function (level) {
    var orig = self.console && self.console[level];
    self.console[level] = function () {
      var parts = [];
      for (var i = 0; i < arguments.length; i++) {
        var a = arguments[i];
        try { parts.push(typeof a === "string" ? a : JSON.stringify(a)); }
        catch (_) { parts.push(String(a)); }
      }
      forward("console", { level: level, text: parts.join(" ") });
      if (orig) try { orig.apply(self.console, arguments); } catch (_) {}
    };
  });

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
