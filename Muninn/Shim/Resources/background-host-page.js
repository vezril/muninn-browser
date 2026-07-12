// background-host-page.js — runs on the hidden host page's main thread.
// It is the ONLY context here that can reach native (webkit.messageHandlers);
// a Worker cannot. So this page is a thin, stateless envelope relay between
// the background.js Worker and the native MessageBroker (ADR-005 refinement,
// ADR-007). It parses no payloads — it forwards envelopes verbatim.
(function () {
  "use strict";

  var ID = location.host; // muninn-ext://<id>/background-host.html
  var mh = (window.webkit && window.webkit.messageHandlers) || {};

  function toNative(name, msg) {
    var h = mh[name];
    if (!h) return Promise.reject(new Error("no native handler: " + name));
    return h.postMessage(msg);
  }

  function audit(msg) { try { toNative("audit", msg); } catch (_) {} }

  var worker;

  function startWorker(manifest) {
    worker = new Worker("background-worker-boot.js", { type: "classic" });

    worker.onmessage = function (e) {
      var d = e.data;
      if (!d || d.__shim === undefined) return;
      switch (d.__shim) {
        case "bootReady":
          worker.postMessage({ __shim: "init", id: ID, manifest: manifest });
          break;
        case "ready":
          audit({ __shim: "hostEvent", event: "workerReady" });
          break;
        case "bgLoaded":
          audit({ __shim: "hostEvent", event: "backgroundLoaded" });
          break;
        case "call":
          // browser.* call from the worker -> native broker (reply expected)
          toNative("broker", d).then(
            function (result) { worker.postMessage({ __shim: "reply", id: d.id, result: result }); },
            function (err) { worker.postMessage({ __shim: "reply", id: d.id, error: String(err && err.message || err) }); }
          );
          break;
        case "console":
        case "workerError":
        case "workerRejection":
        case "audit":
          audit(d);
          break;
      }
    };

    worker.onerror = function (e) {
      audit({ __shim: "workerError", message: e.message, filename: e.filename, lineno: e.lineno });
    };
  }

  // Native pushes events/port traffic to the worker through this hook.
  window.__shimPush = function (env) { if (worker) worker.postMessage(env); };

  // Diagnostic-only: forward a scenario snippet to the worker.
  window.__shimEval = function (code) { if (worker) worker.postMessage({ __shim: "eval", code: code }); };

  // Fetch the manifest over the scheme, then boot the worker.
  fetch("muninn-ext://" + ID + "/manifest.json")
    .then(function (r) { return r.json(); })
    .then(function (m) { startWorker(m); audit({ __shim: "hostEvent", event: "pageReady" }); })
    .catch(function (err) {
      audit({ __shim: "hostEvent", event: "manifestFetchFailed", message: String(err) });
      startWorker({}); // boot anyway so the audit captures the downstream failure
    });
})();
