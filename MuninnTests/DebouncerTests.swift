import XCTest
@testable import Muninn

/// Shields: bounce-tracking debouncing.
final class DebouncerTests: XCTestCase {

    private func dest(_ s: String) -> String? { Debouncer.destination(for: URL(string: s)!)?.absoluteString }

    func testRecoversDestinationFromKnownTrackers() {
        XCTAssertEqual(dest("https://l.facebook.com/l.php?u=https%3A%2F%2Fcats.example%2Fp&h=abc"), "https://cats.example/p")
        XCTAssertEqual(dest("https://out.reddit.com/t3?url=https%3A%2F%2Fexample.com%2Fx&token=1"), "https://example.com/x")
        XCTAssertEqual(dest("https://vk.com/away.php?to=https%3A%2F%2Fsite.org%2Fa"), "https://site.org/a")
    }

    func testPathScopedRule() {
        // steamcommunity.com only debounces under /linkfilter
        XCTAssertEqual(dest("https://steamcommunity.com/linkfilter/?url=https%3A%2F%2Fok.example%2F"), "https://ok.example/")
        XCTAssertNil(dest("https://steamcommunity.com/app/1?url=https%3A%2F%2Fno.example%2F"))
    }

    func testLeavesNonTrackersAlone() {
        XCTAssertNil(dest("https://example.com/?u=https%3A%2F%2Fother.com"))   // not a known tracker host
        XCTAssertNil(dest("https://l.facebook.com/l.php?h=abc"))               // no destination param
    }

    func testIgnoresNonHTTPDestinations() {
        XCTAssertNil(dest("https://out.reddit.com/t3?url=javascript%3Aalert(1)"))
    }
}
