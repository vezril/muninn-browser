// externally-connectable.js — the narrow page MAIN-world `chrome.runtime` bridge
// for `externally_connectable` origins (E6 auth-fork detection).
//
// The account app runs in the page MAIN world and calls
// `chrome.runtime.sendMessage(EXTENSION_ID, msg)` to detect + talk to the
// extension. We expose ONLY `{ id, sendMessage, connect }` here, and ONLY on the
// manifest's externally_connectable hosts — every other origin's MAIN world stays
// completely clean (the S2/ADR-007 guarantee). No native handle is placed in MAIN:
// sendMessage bridges to the already-privileged ISOLATED world via
// `window.postMessage` (same frame), which does the native round-trip to
// `background.js`'s `onMessageExternal`.
//
// `__EC_HOSTS_JSON__` / `__CANONICAL_ID__` are interpolated by InjectionCoordinator.
(function () {
  "use strict";
  var EC_HOSTS = __EC_HOSTS_JSON__;
  var CANONICAL_ID = "__CANONICAL_ID__";

  var host = "";
  try { host = String(location.host).toLowerCase(); } catch (_) {}
  // Not a blessed externally_connectable origin → install NOTHING (MAIN stays clean).
  if (EC_HOSTS.indexOf(host) < 0) return;
  // Don't stomp a real extension API if one somehow exists.
  if (window.chrome && window.chrome.runtime && window.chrome.runtime.sendMessage) return;

  var pending = Object.create(null);
  var seq = 0;

  window.addEventListener("message", function (ev) {
    var d = ev && ev.data;
    if (!d || d.__muninnExtResp !== true) return;
    if (ev.origin !== location.origin) return; // same-frame responses only
    var cb = pending[d.reqId];
    if (!cb) return;
    delete pending[d.reqId];
    cb(d.result);
  });

  // chrome.runtime.sendMessage([extensionId,] message [, options] [, callback])
  function sendMessage() {
    var args = Array.prototype.slice.call(arguments);
    var cb = (typeof args[args.length - 1] === "function") ? args.pop() : null;
    var extId = (typeof args[0] === "string") ? args.shift() : CANONICAL_ID;
    var message = args[0];

    // Only our own extension is reachable (Chrome: a message to another id we don't
    // host simply gets no response).
    if (extId !== CANONICAL_ID) {
      if (cb) { cb(undefined); return undefined; }
      return Promise.resolve(undefined);
    }

    var reqId = "ext" + (++seq);
    var promise = new Promise(function (resolve) {
      pending[reqId] = function (result) { if (cb) { try { cb(result); } catch (_) {} } resolve(result); };
    });
    window.postMessage({ __muninnExt: "sendMessage", reqId: reqId, message: message }, location.origin);
    return cb ? undefined : promise;
  }

  // onConnectExternal is not registered by the vendored background.js; return an
  // inert Port so callers don't throw (parity with the isolated-world stub).
  function connect() {
    var noop = function () {};
    var opts = (arguments.length && arguments[arguments.length - 1]) || {};
    return {
      name: (opts && opts.name) || "",
      onMessage: { addListener: noop, removeListener: noop },
      onDisconnect: { addListener: noop, removeListener: noop },
      postMessage: noop, disconnect: noop,
    };
  }

  var runtime = { id: CANONICAL_ID, sendMessage: sendMessage, connect: connect };
  window.chrome = window.chrome || {};
  window.chrome.runtime = window.chrome.runtime || runtime;
  window.browser = window.browser || {};
  window.browser.runtime = window.browser.runtime || runtime;
})();
