import XCTest
@testable import Muninn

final class QuoteVaultTests: XCTestCase {

    // Calvin's real note shape: title = quote, author frontmatter with a [[wikilink]], body ignored.
    private let sample = """
    ---
    up: "[[Politics MOC]]"
    related:
    created: 2023-12-19
    tags:
      - source/quotes
    author:
      - "[[Jonny Silverhand]]"
    from:
      - "[[Cyberpunk 2077]]"
    ---
    A quote by [[Jonny Silverhand]], the legendary rockerboy. Hater of Arasaka.
    """

    func testExtractsQuoteAuthorAndFrom() {
        let q = QuoteVault.quote(filename: "topple a monument to corporate colonialism",
                                 content: sample, tag: "source/quotes")
        XCTAssertEqual(q?.text, "topple a monument to corporate colonialism")
        XCTAssertEqual(q?.author, "Jonny Silverhand")   // [[ ]] stripped
        XCTAssertEqual(q?.from, "Cyberpunk 2077")       // [[ ]] stripped
    }

    func testRejectsUntaggedNote() {
        let note = """
        ---
        tags:
          - source/books
        author:
          - "Someone"
        ---
        body
        """
        XCTAssertNil(QuoteVault.quote(filename: "x", content: note, tag: "source/quotes"))
    }

    func testNoFrontmatter() {
        XCTAssertNil(QuoteVault.quote(filename: "x", content: "just a note\nno frontmatter", tag: "source/quotes"))
    }

    func testScalarAndInlineTagForms() {
        let scalar = "---\ntags: source/quotes\nauthor: \"[[Jane Doe]]\"\n---\nbody"
        XCTAssertEqual(QuoteVault.quote(filename: "q", content: scalar, tag: "source/quotes")?.author, "Jane Doe")
        let inline = "---\ntags: [source/quotes, misc]\nauthor: Plain Name\n---\nbody"
        let q = QuoteVault.quote(filename: "q", content: inline, tag: "source/quotes")
        XCTAssertEqual(q?.author, "Plain Name")
    }

    func testWikilinkAliasKeepsAlias() {
        XCTAssertEqual(QuoteVault.clean("\"[[Real Name|Display]]\""), "Display")
        XCTAssertEqual(QuoteVault.clean("[[Jonny Silverhand]]"), "Jonny Silverhand")
        XCTAssertEqual(QuoteVault.clean("Plain"), "Plain")
    }

    func testMissingAuthorIsNil() {
        let note = "---\ntags:\n  - source/quotes\n---\nbody"
        let q = QuoteVault.quote(filename: "q", content: note, tag: "source/quotes")
        XCTAssertNotNil(q)
        XCTAssertNil(q?.author)
    }
}
