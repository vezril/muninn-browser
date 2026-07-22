// shim-polyfill.js — runs inside the background-host DedicatedWorker.
// Presents `browser.*` / `chrome.*` to Proton's background.js over a
// postMessage bridge to the host page (which relays to native, ADR-007).
//
// Design (ADR-007, e2-e3 design.md Decision 2):
//   - Every namespace is a Proxy. Modelled members route to native and return
//     a Promise (also invoking a Chrome-style callback if one is passed).
//   - UNMODELLED member access returns a function that logs to the audit
//     channel and returns a rejected Promise — it never throws at property
//     access, so background.js cannot hit `TypeError: X.Y is not a function`.
//   - Payloads are opaque here; the bridge ships them verbatim.
//
// This file is loaded via importScripts BEFORE background.js. It publishes
// self.__shimInit(initData) which the boot script calls once the page sends
// the init envelope (id, manifest, config).
(function () {
  "use strict";

  var CANONICAL_ID = null;
  var MANIFEST = {};
  var pending = Object.create(null); // correlationId -> {resolve, reject}
  var seq = 0;
  var listeners = Object.create(null); // "ns.event" -> [fn]
  var ports = Object.create(null); // portId -> {onMessage:[], onDisconnect:[], post, disconnect}

  function nextId() { return "w" + (++seq); }

  // --- bridge to the host page ---------------------------------------------
  function callNative(ns, method, args) {
    return new Promise(function (resolve, reject) {
      var id = nextId();
      pending[id] = { resolve: resolve, reject: reject };
      self.postMessage({ __shim: "call", id: id, ns: ns, method: method, args: args });
    });
  }

  function audit(ns, member, kind) {
    self.postMessage({ __shim: "audit", ns: ns, member: member, kind: kind, stack: (new Error()).stack });
  }

  // Fork-gate diagnostic: forward worker error TEXT (class + short message, truncated) to native.
  // Native only logs it when MUNINN_FORKGATE is set. Helps see what consumeFork actually throws.
  function forkDiag(text) { try { callNative("__forkdiag", "error", [String(text).slice(0, 160)]); } catch (_) {} }
  self.addEventListener("error", function (e) {
    var er = e && e.error;
    forkDiag((er && er.name ? er.name + ": " : "") + ((er && er.message) || (e && e.message) || e));
  });
  self.addEventListener("unhandledrejection", function (e) {
    var r = e && e.reason;
    forkDiag("reject " + (r && r.name ? r.name + ": " : "") + ((r && r.message) || String(r)));
  });
  function _fmtArgs(args) {
    return Array.prototype.map.call(args, function (x) {
      return x && x.message ? (x.name ? x.name + ": " : "") + x.message : String(x);
    }).join(" ");
  }
  // Wrap error/warn/info so Proton's own logger (nc.warn/info → console) surfaces the real
  // auth/fork failure. `log` is filtered to auth/fork-tagged lines to avoid noise.
  ["error", "warn", "info"].forEach(function (level) {
    var orig = console[level];
    console[level] = function () { try { forkDiag(level + " " + _fmtArgs(arguments)); } catch (_) {} return orig.apply(console, arguments); };
  });
  var _consoleLog = console.log;
  console.log = function () {
    try {
      var s = _fmtArgs(arguments);
      if (/AuthService|[Ff]ork|nauthorized|permission|Error|scope/.test(s)) forkDiag("log " + s);
    } catch (_) {}
    return _consoleLog.apply(console, arguments);
  };

  // Chrome APIs accept an optional trailing callback OR return a Promise.
  function dual(ns, method) {
    return function () {
      var args = Array.prototype.slice.call(arguments);
      var cb = (typeof args[args.length - 1] === "function") ? args.pop() : null;
      var p = callNative(ns, method, args);
      if (cb) {
        p.then(function (r) { self.chrome.runtime.lastError = null; cb(r); },
               function (e) { self.chrome.runtime.lastError = { message: String(e) }; cb(undefined); });
        return undefined;
      }
      return p;
    };
  }

  function eventHub(key) {
    return {
      addListener: function (fn) { (listeners[key] || (listeners[key] = [])).push(fn); },
      removeListener: function (fn) {
        var l = listeners[key]; if (!l) return;
        var i = l.indexOf(fn); if (i >= 0) l.splice(i, 1);
      },
      hasListener: function (fn) { return (listeners[key] || []).indexOf(fn) >= 0; },
    };
  }

  function fireEvent(key, argsArray) {
    var l = listeners[key]; if (!l) return;
    for (var i = 0; i < l.length; i++) {
      try { l[i].apply(null, argsArray); } catch (e) { /* listener errors are the extension's */ }
    }
  }

  // runtime.onMessage delivery. Supports BOTH response contracts:
  //   • callback style — a listener returning `true` keeps the channel open for a
  //     later sendResponse(...); a synchronous sendResponse(...) also works;
  //   • Promise style (modern MV3 / webextension-polyfill) — a listener returning a
  //     thenable resolves to the response. Proton's `lU.onMessage` is async, so this
  //     path is load-bearing for the account handshake (pass-installed, etc.).
  // The response is correlated back to native via respId (E6 cross-context bus).
  function fireMessage(key, message, sender, respId) {
    var l = listeners[key] || [];
    var responded = false;
    function sendResponse(resp) {
      if (responded) return; responded = true;
      if (respId) self.postMessage({ __shim: "response", id: respId, result: resp === undefined ? null : resp });
    }
    var wantsAsync = false;
    for (var i = 0; i < l.length; i++) {
      try {
        var ret = l[i](message, sender, sendResponse);
        if (ret === true) {
          wantsAsync = true; // classic: async sendResponse coming
        } else if (ret && typeof ret.then === "function") {
          wantsAsync = true; // modern: the resolved value IS the response
          ret.then(function (r) { sendResponse(r); }, function () { sendResponse(null); });
        }
      } catch (e) { /* listener errors are the extension's */ }
    }
    // No async responder and nobody answered synchronously → close the channel.
    if (!wantsAsync && !responded && respId) sendResponse(null);
  }

  // --- synchronous members implemented locally -----------------------------
  var SYNC = {
    "runtime.getURL": function (path) {
      var p = String(path || "");
      if (p.charAt(0) === "/") p = p.slice(1);
      return "muninn-ext://" + CANONICAL_ID + "/" + p;
    },
    "runtime.getManifest": function () { return MANIFEST; },
    "runtime.getFrameId": function () { return -1; }, // E5 replaces; harmless default
    "runtime.id": undefined, // set as a value, not a function (below)
  };

  // Members we model natively (async). Anything not listed is audited.
  // NOTE: `connect` is NOT here — Chrome's connect() is synchronous and returns
  // a Port, so a Promise would break `connect().postMessage(...)`. It is
  // special-cased below to return a synchronous inert Port stub (ports are
  // fully implemented in E6 with a real second context).
  var MODELLED = {
    runtime: ["sendMessage", "reload", "getPlatformInfo", "getBrowserInfo",
              "requestUpdateCheck", "sendNativeMessage", "connectNative", "setUninstallURL"],
    storage: ["__local", "__session"], // handled via storage.local/.session objects
    alarms: ["create", "get", "getAll", "clear", "clearAll"],
    tabs: ["query", "get", "getCurrent", "create", "remove", "update", "sendMessage", "reload"],
    action: ["setBadgeText", "setBadgeBackgroundColor", "setIcon", "setTitle", "setPopup", "openPopup"],
    windows: ["create", "update", "get", "getCurrent", "getAll", "remove"],
    permissions: ["request", "contains", "getAll", "remove"],
    scripting: ["executeScript", "insertCSS", "removeCSS", "registerContentScripts"],
    webNavigation: ["getFrame", "getAllFrames"],
    clipboardWrite: [],
  };

  var EVENTS = {
    runtime: ["onMessage", "onMessageExternal", "onConnect", "onConnectExternal",
              "onInstalled", "onStartup", "onUpdateAvailable", "onSuspend"],
    alarms: ["onAlarm"],
    storage: ["onChanged"],
    tabs: ["onUpdated", "onRemoved", "onCreated", "onActivated"],
    permissions: ["onAdded", "onRemoved"],
    webNavigation: ["onCommitted", "onCompleted", "onDOMContentLoaded", "onBeforeNavigate"],
  };

  function makeStorageArea(area) {
    return {
      get: dual("storage", area + ".get"),
      set: dual("storage", area + ".set"),
      remove: dual("storage", area + ".remove"),
      clear: dual("storage", area + ".clear"),
      getBytesInUse: dual("storage", area + ".getBytesInUse"),
    };
  }

  function makeNamespace(ns) {
    var base = Object.create(null);

    // events
    (EVENTS[ns] || []).forEach(function (ev) { base[ev] = eventHub(ns + "." + ev); });

    // storage areas are objects, not methods
    if (ns === "storage") {
      base.local = makeStorageArea("local");
      base.session = makeStorageArea("session");
      base.managed = makeStorageArea("managed");
      base.sync = makeStorageArea("local"); // Pass Safari has no sync; alias local
    }

    // modelled async methods
    (MODELLED[ns] || []).forEach(function (m) {
      if (m.indexOf("__") === 0) return;
      base[m] = dual(ns, m);
    });

    // sync locals + constants
    if (ns === "runtime") {
      base.getURL = SYNC["runtime.getURL"];
      base.getManifest = SYNC["runtime.getManifest"];
      base.getFrameId = SYNC["runtime.getFrameId"];
      base.lastError = null;
      Object.defineProperty(base, "id", { get: function () { return CANONICAL_ID; }, enumerable: true });
      // Synchronous inert Port stub (real ports: E6). Returns immediately so
      // `runtime.connect().postMessage(...)` never hits a TypeError at boot.
      base.connect = function () {
        var disc = [];
        var port = {
          name: "", onMessage: eventHub("__deadPort.onMessage"),
          onDisconnect: { addListener: function (f) { disc.push(f); }, removeListener: function () {} },
          postMessage: function () { /* no peer yet */ },
          disconnect: function () { disc.forEach(function (f) { try { f(port); } catch (_) {} }); },
        };
        return port;
      };
    }

    // Proxy: unmodelled access -> audited rejecting function (never throws)
    return new Proxy(base, {
      get: function (target, prop) {
        if (prop in target) return target[prop];
        if (typeof prop === "symbol") return undefined;
        if (prop === "then") return undefined; // not a thenable
        return function () {
          audit(ns, String(prop), "call");
          return Promise.reject(new Error("muninn-shim: unmodelled " + ns + "." + String(prop)));
        };
      },
    });
  }

  var NAMESPACES = ["runtime", "storage", "alarms", "tabs", "action", "windows",
                    "permissions", "scripting", "webNavigation", "i18n", "extension",
                    "commands", "contextMenus", "notifications", "idle"];

  var api = new Proxy(Object.create(null), {
    get: function (target, prop) {
      if (typeof prop === "symbol") return undefined;
      if (prop === "then") return undefined; // don't let `await browser` create a "then" namespace
      if (!(prop in target)) {
        if (NAMESPACES.indexOf(String(prop)) < 0) audit("<root>", String(prop), "namespace");
        target[prop] = makeNamespace(String(prop));
      }
      return target[prop];
    },
  });

  // --- inbound from page (native pushes + call replies) --------------------
  self.addEventListener("message", function (e) {
    var d = e.data;
    if (!d || d.__shim === undefined) return;
    if (d.__shim === "reply") {
      var p = pending[d.id]; if (!p) return; delete pending[d.id];
      if (d.error) p.reject(new Error(d.error)); else p.resolve(d.result);
    } else if (d.__shim === "push") {
      // native-originated event: { key, args, respId? }
      if (d.key === "runtime.onMessage" || d.key === "runtime.onMessageExternal") {
        var a = d.args || [];
        fireMessage(d.key, a[0], a[1], d.respId);
      } else {
        fireEvent(d.key, d.args || []);
      }
    } else if (d.__shim === "connect") {
      // A client (popup/page) opened a port to us → build the worker-side Port and
      // fire runtime.onConnect (background.js stores it and broadcasts state over it).
      var pid = d.portId, onMsg = [], onDisc = [], open = true;
      var stub = {
        name: d.name || "", sender: d.sender || {},
        onMessage: { addListener: function (f) { onMsg.push(f); }, removeListener: function (f) { var i = onMsg.indexOf(f); if (i >= 0) onMsg.splice(i, 1); } },
        onDisconnect: { addListener: function (f) { onDisc.push(f); }, removeListener: function (f) { var i = onDisc.indexOf(f); if (i >= 0) onDisc.splice(i, 1); } },
        postMessage: function (m) { if (open) self.postMessage({ __shim: "portPost", portId: pid, message: m }); },
        disconnect: function () { if (!open) return; open = false; delete ports[pid]; self.postMessage({ __shim: "portDisconnectHost", portId: pid }); },
      };
      ports[pid] = { onMessage: onMsg, onDisconnect: onDisc, stub: stub, close: function () { open = false; } };
      fireEvent("runtime.onConnect", [stub]);
    } else if (d.__shim === "portMessage") {
      var pt = ports[d.portId]; if (pt) pt.onMessage.forEach(function (f) { try { f(d.message, pt.stub); } catch (_) {} });
    } else if (d.__shim === "portDisconnect") {
      var pd = ports[d.portId]; if (pd) { if (pd.close) pd.close(); pd.onDisconnect.forEach(function (f) { try { f(pd.stub); } catch (_) {} }); delete ports[d.portId]; }
    }
  });

  // --- native fetch proxy (change native-fetch-proxy) ----------------------
  // The worker's origin is muninn-ext://<id>, so cross-origin fetch to the Proton
  // API is CORS-blocked. Route http(s) requests to allowlisted (*.proton.me) hosts
  // through native URLSession (no CORS); everything else uses the platform fetch
  // unchanged (own resources, blob:, data:). Installed at import time — BEFORE the
  // boot script does importScripts("background.js") — so Proton sees the override.
  (function () {
    var nativeFetch = self.fetch ? self.fetch.bind(self) : null;
    function allowed(u) {
      try {
        var url = new URL(u, (self.location && self.location.href) || undefined);
        if (url.protocol !== "https:" && url.protocol !== "http:") return false;
        var h = url.hostname.toLowerCase();
        return h === "proton.me" || h.endsWith(".proton.me");
      } catch (_) { return false; }
    }
    function b64FromBuf(buf) {
      var bytes = new Uint8Array(buf), bin = "";
      for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
      return self.btoa(bin);
    }
    function bufFromB64(b64) {
      var bin = self.atob(b64 || ""), len = bin.length, bytes = new Uint8Array(len);
      for (var i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
      return bytes;
    }
    self.fetch = function (input, init) {
      var url = (typeof input === "string") ? input : (input && input.url);
      // Safe entry probe (host only) — lets the E6 gate see whether the worker calls
      // fetch during the fork, and to which host, before the allowlist decision.
      try {
        var eh = new URL(url, (self.location && self.location.href) || undefined).hostname;
        callNative("__fetch", "probe", [eh]).then(function () {}, function () {});
      } catch (_) {}
      if (!url || !allowed(url)) return nativeFetch ? nativeFetch(input, init) : Promise.reject(new TypeError("no fetch"));
      var req = (typeof input === "object" && input) ? input : null;
      var method = (init && init.method) || (req && req.method) || "GET";
      var headers = {};
      var hsrc = (init && init.headers) || (req && req.headers);
      if (hsrc) {
        if (typeof hsrc.forEach === "function") hsrc.forEach(function (v, k) { headers[k] = v; });
        else if (Array.isArray(hsrc)) hsrc.forEach(function (p) { headers[p[0]] = p[1]; });
        else Object.keys(hsrc).forEach(function (k) { headers[k] = hsrc[k]; });
      }
      function send(bodyBase64) {
        var spec = { url: url, method: method, headers: headers };
        if (bodyBase64) spec.bodyBase64 = bodyBase64;
        return callNative("__fetch", "request", [spec]).then(function (r) {
          if (!r || r.__error) throw new TypeError("Failed to fetch" + (r && r.__error ? " (" + r.__error + ")" : ""));
          var h = new Headers();
          (r.headers || []).forEach(function (p) { try { h.append(p[0], p[1]); } catch (_) {} });
          return new Response(bufFromB64(r.bodyBase64), { status: r.status, statusText: r.statusText, headers: h });
        });
      }
      var body = (init && init.body);
      if (body == null) return send(null);
      if (typeof body === "string") return send(self.btoa(unescape(encodeURIComponent(body))));
      if (body instanceof ArrayBuffer) return send(b64FromBuf(body));
      if (body && body.buffer instanceof ArrayBuffer) return send(b64FromBuf(body.buffer));
      // FormData/Blob/ReadableStream bodies + AbortSignal cancel are deferred (MVP is
      // the fork-consume GET). Fall back to native (honest CORS failure) for those.
      return nativeFetch ? nativeFetch(input, init) : Promise.reject(new TypeError("unsupported body"));
    };
  })();

  // --- init (called by boot script once page sends init) -------------------
  self.__shimInit = function (initData) {
    CANONICAL_ID = initData.id;
    MANIFEST = initData.manifest || {};
    self.chrome = api;
    self.browser = api;
    self.postMessage({ __shim: "ready" });
  };
})();
