import XCTest
@testable import Muninn

/// Shields: tracking query-parameter stripping.
final class QueryStripperTests: XCTestCase {

    private func strip(_ s: String) -> String? { QueryStripper.strip(URL(string: s)!)?.absoluteString }

    func testStripsClickIds() {
        XCTAssertEqual(strip("https://example.com/p?id=5&fbclid=abc&gclid=xyz"), "https://example.com/p?id=5")
        XCTAssertEqual(strip("https://example.com/?msclkid=1&q=hi"), "https://example.com/?q=hi")
    }

    func testStripsUtmAndPrefixes() {
        XCTAssertEqual(strip("https://x.com/a?utm_source=news&utm_medium=email&keep=1"), "https://x.com/a?keep=1")
        XCTAssertEqual(strip("https://x.com/a?hsa_cam=9&real=2"), "https://x.com/a?real=2")
    }

    func testRemovesQueryEntirelyWhenAllTracking() {
        XCTAssertEqual(strip("https://x.com/a?fbclid=abc"), "https://x.com/a")
    }

    func testLeavesCleanURLsUnchanged() {
        XCTAssertNil(strip("https://example.com/p?id=5&q=hi")) // nothing to strip → nil
        XCTAssertNil(strip("https://example.com/path"))
    }

    func testCaseInsensitiveParamNames() {
        XCTAssertEqual(strip("https://x.com/?FBCLID=abc&ok=1"), "https://x.com/?ok=1")
    }
}
