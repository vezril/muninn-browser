import XCTest
@testable import Muninn

/// Reminders: parsing for "Create Reminders List from Page" — structured recipe JSON-LD (decoded from
/// the extraction script's output) and the local-model `{name, items}` fallback.
final class PageListExtractorTests: XCTestCase {

    // MARK: structured recipe decode (the JS emits this shape)

    func testDecodesIngredientsAndSteps() {
        let json = """
        {"title":"Best Pancakes - Site","recipeName":"Fluffy Pancakes",
         "ingredients":["2 cups flour","1 tbsp sugar","2 eggs"],
         "steps":["Mix dry.","Whisk wet.","Cook on griddle."]}
        """
        let r = PageListExtractor.decode(json)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.ingredients.count, 3)
        XCTAssertEqual(r?.steps.count, 3)
        XCTAssertEqual(r?.listName, "Fluffy Pancakes")   // recipeName preferred over title
        XCTAssertTrue(r?.hasStructuredData ?? false)
    }

    func testFallsBackToTitleWhenNoRecipeName() {
        let json = #"{"title":"My Page","ingredients":["a"],"steps":[]}"#
        let r = PageListExtractor.decode(json)
        XCTAssertEqual(r?.listName, "My Page")
        XCTAssertTrue(r?.hasStructuredData ?? false)
    }

    func testNoStructuredData() {
        let json = #"{"title":"Blog post","ingredients":[],"steps":[]}"#
        let r = PageListExtractor.decode(json)
        XCTAssertNotNil(r)
        XCTAssertFalse(r?.hasStructuredData ?? true)
    }

    // MARK: model fallback decode (tolerant of prose / fences)

    func testDecodesModelListPlain() {
        let raw = #"{"name":"Groceries","items":["milk","eggs","bread"]}"#
        let list = PageListExtractor.decodeModelList(raw)
        XCTAssertEqual(list?.name, "Groceries")
        XCTAssertEqual(list?.items, ["milk", "eggs", "bread"])
    }

    func testDecodesModelListWithFencesAndProse() {
        let raw = """
        Sure! Here is the list:
        ```json
        {"name": "Trip Packing", "items": ["passport", "charger"]}
        ```
        Let me know if you need more.
        """
        let list = PageListExtractor.decodeModelList(raw)
        XCTAssertEqual(list?.name, "Trip Packing")
        XCTAssertEqual(list?.items.count, 2)
    }

    func testRejectsEmptyItems() {
        XCTAssertNil(PageListExtractor.decodeModelList(#"{"name":"X","items":[]}"#))
        XCTAssertNil(PageListExtractor.decodeModelList("no json here"))
    }
}
