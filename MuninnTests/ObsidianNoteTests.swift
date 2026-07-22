import XCTest
@testable import Muninn

/// Obsidian note writer: filename sanitising, frontmatter, de-duplication.
final class ObsidianNoteTests: XCTestCase {

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("muninn-obsidian-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testSanitizesFilename() {
        XCTAssertEqual(ObsidianNote.sanitizedFilename("Hello / World: Test?"), "Hello World Test")
        XCTAssertEqual(ObsidianNote.sanitizedFilename("   "), "Untitled")
        XCTAssertEqual(ObsidianNote.sanitizedFilename("a\\b*c\"d"), "a b c d")
    }

    func testFrontmatterHasTitleAndURL() {
        let fm = ObsidianNote.frontmatter(title: "My \"Page\"", url: "https://example.com")
        XCTAssertTrue(fm.contains("title: \"My \\\"Page\\\"\""))
        XCTAssertTrue(fm.contains("url: https://example.com"))
        XCTAssertTrue(fm.contains("tags: [web-clip]"))
    }

    func testCreatesNoteAndDedupes() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = try ObsidianNote.create(title: "Same Title", url: "https://a.example", summary: nil, in: dir)
        let b = try ObsidianNote.create(title: "Same Title", url: "https://a.example", summary: "TL;DR: hi", in: dir)
        XCTAssertEqual(a.lastPathComponent, "Same Title.md")
        XCTAssertEqual(b.lastPathComponent, "Same Title 1.md")   // de-duplicated
        let body = try String(contentsOf: b, encoding: .utf8)
        XCTAssertTrue(body.contains("# Same Title"))
        XCTAssertTrue(body.contains("TL;DR: hi"))
        XCTAssertTrue(body.contains("[https://a.example](https://a.example)"))
    }
}
