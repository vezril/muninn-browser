import Foundation
import WebKit

/// FR-9 frame registry (E5 task 5). Assigns Chrome-convention frame ids — the main
/// frame is `0`, subframes get stable positive integers — so the shim can answer
/// `webNavigation.getFrame` / `getAllFrames` and resolve `runtime.getFrameId` to the
/// calling content-script's frame.
///
/// WebKit exposes no public stable frame identifier on `WKFrameInfo` (only
/// `isMainFrame` / `request` / `securityOrigin` on the macOS 26.2 SDK), so identity
/// is keyed on `(isMainFrame, securityOrigin, url)`. The id-assignment core is pure
/// (`resolve(isMain:url:originKey:parentId:)`) so it is unit-testable without a
/// `WKFrameInfo` (which has no public initializer).
///
/// Single-tab scope (MVP): one registry per page. `tabId` from
/// `webNavigation.get*Frames` is ignored — there is one tab.
@MainActor
final class FrameRegistry {
    struct Frame { let id: Int; let url: String; let parentFrameId: Int }

    static let mainFrameId = 0
    static let noParent = -1   // Chrome: the main frame's parentFrameId

    private var byKey: [String: Int] = [:]
    private var records: [Int: Frame] = [:]
    private var nextId = 1

    // MARK: - pure core (unit-testable; no WKFrameInfo)

    /// Resolve a frame to its id, registering it on first sight. The main frame is
    /// always `0`; subframes get a stable positive id keyed on origin+url.
    @discardableResult
    func resolve(isMain: Bool, url: String, originKey: String, parentId: Int) -> Int {
        if isMain {
            records[Self.mainFrameId] = Frame(id: Self.mainFrameId, url: url, parentFrameId: Self.noParent)
            return Self.mainFrameId
        }
        // KNOWN LIMITATION: keying on origin+url is what makes ids STABLE across the
        // many messages one frame sends (resolve() runs per message), but it collapses
        // distinct subframes that share a URL into one id — most concretely several
        // `about:blank` / `about:srcdoc` iframes. A monotonic ordinal would distinguish
        // them but break that per-message stability, so it's not used. WKFrameInfo
        // exposes no stable identity to do better; multi-identical-iframe autofill is
        // post-MVP (Spike B risk #2). Codified in FrameRegistryTests.
        let key = "\(originKey)\n\(url)"
        if let id = byKey[key] {
            // Refresh the url (same frame, e.g. re-navigated to the same key).
            records[id] = Frame(id: id, url: url, parentFrameId: records[id]?.parentFrameId ?? parentId)
            return id
        }
        let id = nextId; nextId += 1
        byKey[key] = id
        records[id] = Frame(id: id, url: url, parentFrameId: parentId)
        return id
    }

    /// All known frames as `webNavigation.getAllFrames` details, ordered by id.
    func all() -> [[String: Any]] {
        records.values.sorted { $0.id < $1.id }.map {
            ["frameId": $0.id, "parentFrameId": $0.parentFrameId, "url": $0.url]
        }
    }

    /// `webNavigation.getFrame({frameId})` — details or nil for an unknown id.
    func frame(_ id: Int) -> [String: Any]? {
        guard let f = records[id] else { return nil }
        return ["frameId": f.id, "parentFrameId": f.parentFrameId, "url": f.url]
    }

    /// New main-frame navigation invalidates the subframe tree (the main frame id
    /// stays `0`; its url is refreshed on the next `resolve`).
    func resetSubframes() {
        byKey.removeAll(); nextId = 1
        if let main = records[Self.mainFrameId] { records = [Self.mainFrameId: main] } else { records.removeAll() }
    }

    // MARK: - WKFrameInfo bridge

    /// Resolve a live `WKFrameInfo` (from a `WKScriptMessage` or navigation) to its
    /// frame id, registering it if new.
    @discardableResult
    func resolve(_ frameInfo: WKFrameInfo, parentId: Int = FrameRegistry.mainFrameId) -> Int {
        let url = frameInfo.request.url?.absoluteString ?? ""
        let origin = frameInfo.securityOrigin
        let originKey = "\(origin.protocol)://\(origin.host):\(origin.port)"
        return resolve(isMain: frameInfo.isMainFrame, url: url,
                       originKey: originKey, parentId: frameInfo.isMainFrame ? Self.noParent : parentId)
    }
}
