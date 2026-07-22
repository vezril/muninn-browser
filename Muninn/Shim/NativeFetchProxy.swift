import Foundation

/// Native `URLSession` fetch proxy (change `native-fetch-proxy`). Gives the extension
/// worker CORS-bypassed network access to its `host_permissions` origins: the worker's
/// `fetch` is routed here (via the broker) and performed natively, which is not subject
/// to web CORS — reproducing the host-permission privilege a real browser grants.
///
/// Deny-by-default (the SSRF boundary): only `https` requests to the `*.proton.me`
/// allowlist are performed, re-checked across redirects. Reachability is further limited
/// by wiring the `__fetch` broker route ONLY on the background host (not on page content
/// worlds) — see `BackgroundHost`/`MessageBroker`.
///
/// Cookies live in a DEDICATED `HTTPCookieStorage` (the extension's own Proton session),
/// isolated from `URLSession.shared` and the WK data stores — this is what the auth-fork
/// `selector` handoff expects, and it side-steps the Decision-4 cookie topology.
actor NativeFetchProxy {

    /// Sendable result carried back across the actor → main-actor boundary (Swift 6).
    /// The broker converts it to the `[String:Any]` JS reply. `error` non-nil ⇒ failure.
    struct FetchResult: Sendable {
        var status = 0
        var statusText = ""
        var headers: [[String]] = []
        var bodyBase64 = ""
        var finalURL = ""
        var redirected = false
        var error: String?
    }

    /// Proper host-suffix allowlist (Chrome match-pattern host semantics). NEVER a
    /// substring test: `evilproton.me` / `proton.me.evil.com` must fail.
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "proton.me" || host.hasSuffix(".proton.me")
    }

    /// Request headers the shim must never let JS set (cookies are native-managed;
    /// Host/Content-Length are computed by URLSession).
    private static let forbiddenHeaders: Set<String> = ["cookie", "host", "content-length"]

    private let session: URLSession
    private let redirectGuard: RedirectGuard

    init() {
        let config = URLSessionConfiguration.ephemeral
        // Dedicated cookie jar = the extension's Proton session, isolated from .shared.
        config.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "muninn.ext.fetchproxy")
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let guardDelegate = RedirectGuard()
        self.redirectGuard = guardDelegate
        self.session = URLSession(configuration: config, delegate: guardDelegate, delegateQueue: nil)
    }

    /// Perform a proxied request from Sendable primitives (parsed on the main actor).
    /// Never throws across the bus — failures come back as `FetchResult.error`.
    func perform(url urlString: String, method: String,
                 headers: [String: String], bodyBase64: String?) async -> FetchResult {
        guard let url = URL(string: urlString) else { return FetchResult(error: "bad url") }
        guard Self.isAllowed(url) else { return FetchResult(error: "host not allowlisted") }

        // Fork-gate diagnostic: log only host + path with the trailing id (selector) REDACTED, and
        // the resulting status/error. NEVER logs headers or body (cookies / session tokens).
        let forkGate = ProcessInfo.processInfo.environment["MUNINN_FORKGATE"] != nil
        func forkLog(_ msg: String) {
            guard forkGate else { return }
            let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Muninn/fork-gate.log")
            let line = "\(Date().ISO8601Format()) \(msg)\n"
            if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.data(using: .utf8)?.write(to: u) }
        }
        if forkGate, url.path.contains("/sessions/forks") {
            let comps = url.pathComponents
            let redacted = comps.count > 1 ? comps.dropLast().joined(separator: "/") + "/<redacted>" : url.path
            forkLog("proxy \(method.uppercased()) \(url.host ?? "?")\(redacted)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method.uppercased()
        for (k, v) in headers where !Self.forbiddenHeaders.contains(k.lowercased()) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if let b64 = bodyBase64, let body = Data(base64Encoded: b64) { req.httpBody = body }

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return FetchResult(error: "non-http response") }
            if forkGate, url.path.contains("/sessions/forks") { forkLog("proxy -> status \(http.statusCode)") }
            // Final-hop allowlist guard (defense-in-depth beyond the redirect delegate).
            if let finalURL = http.url, !Self.isAllowed(finalURL) { return FetchResult(error: "redirected off allowlist") }
            var headerPairs: [[String]] = []
            for (k, v) in http.allHeaderFields { headerPairs.append([String(describing: k), String(describing: v)]) }
            let finalURLStr = http.url?.absoluteString ?? urlString
            return FetchResult(
                status: http.statusCode,
                statusText: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                headers: headerPairs,
                bodyBase64: data.base64EncodedString(),
                finalURL: finalURLStr,
                redirected: finalURLStr != urlString,
                error: nil)
        } catch is CancellationError {
            return FetchResult(error: "aborted")
        } catch {
            if forkGate, url.path.contains("/sessions/forks") { forkLog("proxy -> error \(String(describing: error))") }
            return FetchResult(error: String(describing: error))
        }
    }
}

/// URLSession task delegate that re-checks the allowlist on every redirect and stops the
/// redirect chain if it leaves the allowlist (prevents an open redirect from carrying the
/// extension's cookies off-allowlist). Immutable → safe to share across the delegate queue.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, NativeFetchProxy.isAllowed(url) { completionHandler(request) }
        else { completionHandler(nil) } // stop: off-allowlist redirect
    }
}
