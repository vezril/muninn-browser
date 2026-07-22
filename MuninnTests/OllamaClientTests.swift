import XCTest
@testable import Muninn

/// ollama-connection: the pure parsing of `/api/tags` and the `/api/generate` NDJSON stream.
final class OllamaClientTests: XCTestCase {

    func testParseTags() {
        let json = """
        {"models":[{"name":"llama3.2:latest"},{"name":"qwen2.5-coder:7b"}]}
        """.data(using: .utf8)!
        XCTAssertEqual(OllamaClient.parseTags(json), ["llama3.2:latest", "qwen2.5-coder:7b"])
    }

    func testParseTagsEmptyOrGarbage() {
        XCTAssertEqual(OllamaClient.parseTags(Data("{}".utf8)), [])
        XCTAssertEqual(OllamaClient.parseTags(Data("not json".utf8)), [])
    }

    func testParseGenerateLine() {
        let chunk = OllamaClient.parseGenerateLine(#"{"response":"Hel","done":false}"#)
        XCTAssertEqual(chunk?.text, "Hel")
        XCTAssertEqual(chunk?.done, false)
    }

    func testParseGenerateDone() {
        let chunk = OllamaClient.parseGenerateLine(#"{"response":"","done":true}"#)
        XCTAssertEqual(chunk?.text, "")
        XCTAssertEqual(chunk?.done, true)
    }

    func testParseGenerateBlankLineIgnored() {
        XCTAssertNil(OllamaClient.parseGenerateLine("   "))
        XCTAssertNil(OllamaClient.parseGenerateLine("garbage"))
    }

    func testParseChatLine() {
        let chunk = OllamaClient.parseChatLine(#"{"message":{"role":"assistant","content":"Hi"},"done":false}"#)
        XCTAssertEqual(chunk?.text, "Hi")
        XCTAssertEqual(chunk?.done, false)
        XCTAssertEqual(OllamaClient.parseChatLine(#"{"message":{"role":"assistant","content":""},"done":true}"#)?.done, true)
        XCTAssertNil(OllamaClient.parseChatLine("  "))
    }

    func testChatStreamReassembles() {
        let lines = [
            #"{"message":{"role":"assistant","content":"Hel"},"done":false}"#,
            #"{"message":{"role":"assistant","content":"lo"},"done":true}"#,
        ]
        var out = ""
        for l in lines { if let c = OllamaClient.parseChatLine(l) { out += c.text; if c.done { break } } }
        XCTAssertEqual(out, "Hello")
    }

    func testStreamReassembles() {
        // The concatenation of response chunks is the full answer.
        let lines = [
            #"{"response":"Hel","done":false}"#,
            #"{"response":"lo","done":false}"#,
            #"{"response":"!","done":true}"#,
        ]
        var out = ""
        for l in lines {
            guard let c = OllamaClient.parseGenerateLine(l) else { continue }
            out += c.text
            if c.done { break }
        }
        XCTAssertEqual(out, "Hello!")
    }
}
