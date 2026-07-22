import XCTest
@testable import Muninn

/// Share-link cleaning: platform share-attribution params are stripped while meaningful params survive.
final class ShareLinkCleanerTests: XCTestCase {

    private func clean(_ s: String) -> String {
        ShareLinkCleaner.clean(URL(string: s)!).absoluteString
    }

    // The canonical example from the request.
    func testYouTubeShareSiRemoved() {
        XCTAssertEqual(clean("https://youtu.be/dQw4w9WgXcQ?si=NblIBgit-qHN7MoH"),
                       "https://youtu.be/dQw4w9WgXcQ")
    }

    func testYouTubeKeepsTimestampAndPlaylist() {
        // si stripped, t (timestamp) + list (playlist) kept.
        XCTAssertEqual(clean("https://www.youtube.com/watch?v=abc&t=42&si=XYZ&list=PL123"),
                       "https://www.youtube.com/watch?v=abc&t=42&list=PL123")
    }

    func testHostSuffixInherits() {
        XCTAssertEqual(clean("https://m.youtube.com/watch?v=abc&si=XYZ"),
                       "https://m.youtube.com/watch?v=abc")
    }

    func testTwitterSAndTRemoved() {
        XCTAssertEqual(clean("https://x.com/user/status/123?s=20&t=AbCdEf"),
                       "https://x.com/user/status/123")
    }

    func testInstagramIgshRemovedIndexKept() {
        XCTAssertEqual(clean("https://www.instagram.com/p/ABC/?igsh=Zzz&img_index=2"),
                       "https://www.instagram.com/p/ABC/?img_index=2")
    }

    func testTikTokShareParamsRemoved() {
        XCTAssertEqual(clean("https://www.tiktok.com/@u/video/7?_r=1&_t=8xyz&is_from_webapp=1"),
                       "https://www.tiktok.com/@u/video/7")
    }

    func testSpotifySiRemoved() {
        XCTAssertEqual(clean("https://open.spotify.com/track/abc?si=deadbeef"),
                       "https://open.spotify.com/track/abc")
    }

    func testRedditKeepsContextDropsShareId() {
        XCTAssertEqual(clean("https://www.reddit.com/r/x/comments/1/t/?context=3&share_id=zzz"),
                       "https://www.reddit.com/r/x/comments/1/t/?context=3")
    }

    func testAmazonPathRefAndParamsStripped() {
        XCTAssertEqual(clean("https://www.amazon.com/dp/B00TEST/ref=sr_1_1?tag=aff-20&th=1&psc=1"),
                       "https://www.amazon.com/dp/B00TEST")
    }

    func testGlobalUtmAndClickIdsStrippedAnywhere() {
        // No host rule for example.com, but global QueryStripper params still go.
        XCTAssertEqual(clean("https://example.com/p?utm_source=news&fbclid=abc&keep=1"),
                       "https://example.com/p?keep=1")
    }

    func testCleanUrlUnchanged() {
        XCTAssertEqual(clean("https://example.com/article?page=2"),
                       "https://example.com/article?page=2")
        XCTAssertEqual(clean("https://youtu.be/dQw4w9WgXcQ"),
                       "https://youtu.be/dQw4w9WgXcQ")
    }
}
