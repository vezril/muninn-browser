// content-polyfill.js — the shim's full browser.* surface for the page ISOLATED
// world (never MAIN). Proxy catch-all so Proton's orchestrator.js/fork.js boot
// without throwing on unmodelled access (content-side S1); unmodelled access is
// audited and returns a rejecting call. Transport is
// webkit.messageHandlers.brokerIsolated (calls) + __muninnContentPush (inbound).
//
// Injected at document_start in the isolated world, AFTER a bootstrap user
// script sets globalThis.__MUNINN = { id, manifest }.
(function () {
  "use strict";
  var g = (typeof globalThis !== "undefined") ? globalThis : this;
  var BOOT = g.__MUNINN || {};
  var CANONICAL_ID = BOOT.id || "ghmbeldphafepmbegfdlkpapadhbakde";
  var MANIFEST = BOOT.manifest || {};
  var mh = (g.webkit && g.webkit.messageHandlers) || {};
  var broker = mh.brokerIsolated;
  var listeners = Object.create(null); // "ns.event" -> [fn]
  // This frame's id. Synchronously distinguish the main frame (id 0, correct
  // immediately) from a subframe (-1 = "pending", never a false 0) via reference
  // identity, which is allowed cross-origin. The real subframe id is resolved from
  // native on boot (below) and replaces the -1.
  var currentFrameId = 0;
  try { if (g.window && g.window.top !== g.window.self) currentFrameId = -1; } catch (_) { currentFrameId = -1; }
  var portReg = Object.create(null); // portId -> {msg:[], disc:[], port, close}
  var portSeq = 0;

  function callNative(ns, method, args) {
    if (!broker) return Promise.reject(new Error("no isolated broker"));
    return broker.postMessage({ ns: ns, method: method, args: args });
  }
  function audit(ns, member, kind) {
    if (broker) broker.postMessage({ ns: "__audit", method: "record",
      args: [{ ns: ns, member: member, kind: kind, stack: (new Error()).stack }] });
  }

  function dual(ns, method) {
    return function () {
      var args = Array.prototype.slice.call(arguments);
      var cb = (typeof args[args.length - 1] === "function") ? args.pop() : null;
      var p = callNative(ns, method, args);
      if (cb) { p.then(function (r) { cb(r); }, function () { cb(undefined); }); return; }
      return p;
    };
  }
  function eventHub(key) {
    return {
      addListener: function (f) { (listeners[key] || (listeners[key] = [])).push(f); },
      removeListener: function (f) { var l = listeners[key]; if (!l) return; var i = l.indexOf(f); if (i >= 0) l.splice(i, 1); },
      hasListener: function (f) { return (listeners[key] || []).indexOf(f) >= 0; },
    };
  }

  var EVENTS = {
    runtime: ["onMessage", "onMessageExternal", "onConnect", "onInstalled", "onStartup"],
    storage: ["onChanged"],
    tabs: ["onUpdated", "onRemoved", "onActivated"],
  };
  var SYNC_RUNTIME = {
    getURL: function (p) { var s = String(p || ""); if (s.charAt(0) === "/") s = s.slice(1); return "muninn-ext://" + CANONICAL_ID + "/" + s; },
    getManifest: function () { return MANIFEST; },
    // Safari-form runtime.getFrameId(target): 0/undefined/window/self → THIS frame.
    // Main frame → 0 immediately; a subframe → -1 ("pending") until native resolves
    // its real id, so a subframe is NEVER mistaken for the main frame. An
    // iframe-element target (Proton's client.js autofill path) resolves the CHILD
    // frame in Safari; that is post-MVP (Spike B risk #2). This best-effort returns
    // this frame's id so orchestrator's `"getFrameId" in runtime` check passes and
    // main-frame flows resolve correctly.
    getFrameId: function () { return currentFrameId; },
  };

  function makeNamespace(ns) {
    var base = Object.create(null);
    (EVENTS[ns] || []).forEach(function (ev) { base[ev] = eventHub(ns + "." + ev); });
    if (ns === "storage") {
      ["local", "session", "managed"].forEach(function (area) {
        base[area] = { get: dual("storage", area + ".get"), set: dual("storage", area + ".set"),
                       remove: dual("storage", area + ".remove"), clear: dual("storage", area + ".clear"),
                       getBytesInUse: dual("storage", area + ".getBytesInUse") };
      });
      base.sync = base.local;
    }
    if (ns === "runtime") {
      base.getURL = SYNC_RUNTIME.getURL; base.getManifest = SYNC_RUNTIME.getManifest;
      base.getFrameId = SYNC_RUNTIME.getFrameId; base.lastError = null;
      Object.defineProperty(base, "id", { get: function () { return CANONICAL_ID; }, enumerable: true });
      // Real cross-context port (E7): connect(id?, {name}?) → a live port to the host
      // worker's onConnect, over the bus. Synchronous return (Chrome contract).
      base.connect = function (a, b) {
        var info = (b && typeof b === "object") ? b : (a && typeof a === "object") ? a : {};
        var name = info.name || "";
        portSeq += 1; var portId = "cport-" + portSeq;
        var msgL = [], discL = [], open = true;
        var port = {
          name: name,
          onMessage: { addListener: function (f) { msgL.push(f); },
                       removeListener: function (f) { var i = msgL.indexOf(f); if (i >= 0) msgL.splice(i, 1); } },
          onDisconnect: { addListener: function (f) { discL.push(f); },
                          removeListener: function (f) { var i = discL.indexOf(f); if (i >= 0) discL.splice(i, 1); } },
          postMessage: function (m) { if (open && broker) broker.postMessage({ ns: "__port", method: "message", args: [portId, m] }); },
          disconnect: function () { if (!open) return; open = false; delete portReg[portId];
                                    if (broker) broker.postMessage({ ns: "__port", method: "disconnect", args: [portId] }); },
        };
        portReg[portId] = { msg: msgL, disc: discL, port: port, close: function () { open = false; } };
        if (broker) broker.postMessage({ ns: "__port", method: "connect", args: [portId, name] });
        return port;
      };
    }
    return new Proxy(base, {
      get: function (target, prop) {
        if (prop in target) return target[prop];
        if (typeof prop === "symbol" || prop === "then") return undefined;
        // Route any non-locally-modelled method to native (which handles known
        // ones — sendMessage, tabs.*, etc. — and throws for truly-unknown). Audit
        // for visibility; native throwing surfaces as a rejection, not a crash.
        return function () {
          var args = Array.prototype.slice.call(arguments);
          var cb = (typeof args[args.length - 1] === "function") ? args.pop() : null;
          audit(ns, String(prop), "call");
          var p = callNative(ns, String(prop), args);
          if (cb) { p.then(function (r) { cb(r); }, function () { cb(undefined); }); return; }
          return p;
        };
      },
    });
  }

  var KNOWN = ["runtime", "storage", "alarms", "tabs", "action", "windows", "permissions",
               "scripting", "webNavigation", "i18n", "extension", "commands", "contextMenus", "notifications", "idle", "app"];
  var api = new Proxy(Object.create(null), {
    get: function (target, prop) {
      if (typeof prop === "symbol" || prop === "then") return undefined;
      if (!(prop in target)) {
        if (KNOWN.indexOf(String(prop)) < 0) audit("<root>", String(prop), "namespace");
        target[prop] = makeNamespace(String(prop));
      }
      return target[prop];
    },
  });

  // Inbound native → content (events, onMessage delivery, port traffic).
  g.__muninnContentPush = function (env) {
    if (!env || !env.key) return;
    if (env.key === "__port.message") {
      var pm = portReg[env.portId];
      if (pm) pm.msg.forEach(function (f) { try { f(env.message, pm.port); } catch (_) {} });
      return;
    }
    if (env.key === "__port.disconnect") {
      var pd = portReg[env.portId];
      if (pd) { pd.close(); delete portReg[env.portId]; pd.disc.forEach(function (f) { try { f(pd.port); } catch (_) {} }); }
      return;
    }
    var l = listeners[env.key] || [];
    var a = env.args || [];
    if (env.key === "runtime.onMessage" || env.key === "runtime.onMessageExternal") {
      var responded = false;
      function sendResponse(r) { if (responded) return; responded = true;
        if (env.respId && broker) broker.postMessage({ ns: "__respond", method: "resolve", args: [env.respId, r === undefined ? null : r] }); }
      var wantsAsync = false;
      for (var i = 0; i < l.length; i++) { try { if (l[i](a[0], a[1], sendResponse) === true) wantsAsync = true; } catch (_) {} }
      if (!wantsAsync && !responded && env.respId && broker) broker.postMessage({ ns: "__respond", method: "resolve", args: [env.respId, null] });
    } else {
      for (var j = 0; j < l.length; j++) { try { l[j].apply(null, a); } catch (_) {} }
    }
  };

  // Install ONLY in this isolated world's global (never MAIN).
  g.chrome = api;
  g.browser = api;

  // externally_connectable bridge (E6): the MAIN-world chrome.runtime shim (only
  // present on manifest externally_connectable hosts) posts sendMessage here via
  // window.postMessage; relay to native onMessageExternal and post the response
  // back to MAIN. Double-gated: only when THIS frame's own host is blessed and the
  // message is same-origin (a hostile cross-origin frame can't spoof it, and the
  // native side re-checks the origin). Uses the DOM window (shared with MAIN).
  var EC_HOSTS = [];
  try {
    var ecm = (MANIFEST.externally_connectable && MANIFEST.externally_connectable.matches) || [];
    EC_HOSTS = ecm.map(function (p) { try { return new URL(p.replace("/*", "/")).host.toLowerCase(); } catch (_) { return null; } })
                  .filter(Boolean);
  } catch (_) {}
  try {
    if (broker && EC_HOSTS.indexOf(String(window.location.host).toLowerCase()) >= 0) {
      window.addEventListener("message", function (ev) {
        var d = ev && ev.data;
        if (!d || d.__muninnExt !== "sendMessage") return;
        if (ev.origin !== window.location.origin) return; // same-frame only
        var reqId = d.reqId;
        function reply(result) {
          window.postMessage({ __muninnExtResp: true, reqId: reqId, result: (result === undefined ? null : result) },
                             window.location.origin);
        }
        callNative("runtime", "__externalMessage", [d.message]).then(reply, function () { reply(null); });
      });
    }
  } catch (_) {}

  // Resolve THIS frame's id from native (message.frameInfo → FrameRegistry). Async,
  // but getFrameId's callers run after boot, so the cached id is ready in time; the
  // main frame's 0 default is correct until then.
  if (broker) {
    broker.postMessage({ ns: "runtime", method: "__resolveFrameId", args: [] })
      .then(function (id) { if (typeof id === "number") currentFrameId = id; }, function () {});
  }
})();
