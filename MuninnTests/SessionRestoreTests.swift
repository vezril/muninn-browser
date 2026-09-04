import XCTest
@testable import Muninn

/// Session-restore persistence: `SidebarState` now carries regular tabs + the active-tab index,
/// and must still decode older payloads that predate those fields.
final class SessionRestoreTests: XCTestCase {

    func testRoundTripsRegularTabsAndActiveIndex() throws {
        let ws = UUID()
        let state = SidebarState(
            tabs: [
                SavedTab(url: "https://example.com/", title: "Example", kind: .regular, workspaceId: ws.uuidString),
                SavedTab(url: "https://apple.com/", title: "Apple", kind: .pinned, workspaceId: ws.uuidString),
            ],
            activeTabIndex: 1)
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(SidebarState.self, from: data)
        XCTAssertEqual(back.tabs.count, 2)
        XCTAssertEqual(back.tabs[0].kind, .regular)
        XCTAssertEqual(back.tabs[0].url, "https://example.com/")
        XCTAssertEqual(back.activeTabIndex, 1)
    }

    /// A pre-restore sidebar.json (all the fields that existed then, but no `activeTabIndex`) must
    /// still decode — the new field is optional, so its absence falls back to the first tab.
    func testDecodesLegacyPayloadWithoutActiveIndex() throws {
        let json = """
        { "tabs": [ { "url": "https://apple.com/", "title": "Apple", "kind": "pinned" } ],
          "folders": [], "workspaces": [], "profiles": [], "routingRules": [],
          "toolsSidebarOpen": false, "liveCalendars": [] }
        """
        let state = try JSONDecoder().decode(SidebarState.self, from: Data(json.utf8))
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertNil(state.activeTabIndex)   // absent → nil → falls back to the first tab on restore
    }
}
