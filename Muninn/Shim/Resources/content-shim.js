// content-shim.js — the shim's content-script half, injected into an ISOLATED
// WKContentWorld (never the page MAIN world). Provides the minimal `browser`/
// `chrome` surface that Proton's fork.js needs to relay the auth handshake, and
// talks straight to native via webkit.messageHandlers — which are registered
// only for this isolated world, so the page MAIN world cannot reach them.
//
// This is the S2 / e3-hardening minimal bridge, NOT the full FR-9/E5 injector.
(function () {
  "use strict";

  var mh = (window.webkit && window.webkit.messageHandlers) || {};
  var broker = mh.brokerIsolated;
  var listeners = { message: [], external: [] };

  function callNative(ns, method, args) {
    if (!broker) return Promise.reject(new Error("no isolated broker handler"));
    return broker.postMessage({ ns: ns, method: method, args: args });
  }

  var runtime = {
    id: "ghmbeldphafepmbegfdlkpapadhbakde",
    getURL: function (p) { return "muninn-ext://" + this.id + "/" + String(p || "").replace(/^\//, ""); },
    sendMessage: function () {
      var args = Array.prototype.slice.call(arguments);
      var cb = (typeof args[args.length - 1] === "function") ? args.pop() : null;
      var p = callNative("runtime", "sendMessage", args);
      if (cb) { p.then(cb, function () { cb(undefined); }); return; }
      return p;
    },
    onMessage: hub("message"),
    onMessageExternal: hub("external"),
    connect: function () {
      return { name: "", postMessage: function () {},
               onMessage: hub("message"), onDisconnect: hub("message"),
               disconnect: function () {} };
    },
    lastError: null,
  };

  function hub(key) {
    return {
      addListener: function (f) { listeners[key].push(f); },
      removeListener: function (f) { var i = listeners[key].indexOf(f); if (i >= 0) listeners[key].splice(i, 1); },
      hasListener: function (f) { return listeners[key].indexOf(f) >= 0; },
    };
  }

  var api = { runtime: runtime };
  // Install ONLY in this isolated world's global. The page MAIN world has a
  // separate global and never sees these (that is the S2 guarantee).
  this.chrome = api;
  this.browser = api;

  // Native → content pushes (delivered via evaluateJavaScript in this world).
  this.__muninnContentPush = function (env) {
    if (env && env.key === "runtime.onMessage") {
      listeners.message.forEach(function (f) { try { f.apply(null, env.args || []); } catch (_) {} });
    }
  };

  // S2 probe: report what this world sees (used by the isolation test).
  this.__muninnWorldProbe = function () {
    return { hasChrome: typeof this.chrome !== "undefined",
             hasBroker: !!broker, id: runtime.id };
  };
}).call(typeof globalThis !== "undefined" ? globalThis : this);
