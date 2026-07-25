import XCTest
@testable import Muninn

/// The pure part of the Hermes integration: flattening a conversation into a one-shot prompt.
/// (Spawning the CLI itself is not unit-tested — it shells out to the user's local agent.)
@MainActor
final class HermesClientTests: XCTestCase {

    func testFlattensRolesWithLabels() {
        let prompt = HermesClient.prompt(from: [
            ChatMessage(role: .user, text: "hello"),
            ChatMessage(role: .assistant, text: "hi there"),
            ChatMessage(role: .user, text: "what's 2+2?"),
        ])
        XCTAssertEqual(prompt, "User: hello\n\nAssistant: hi there\n\nUser: what's 2+2?")
    }

    func testPageContextIsLabelledAsContext() {
        let prompt = HermesClient.prompt(from: [
            ChatMessage(role: .system, text: "Page: Example\nhttps://example.com"),
            ChatMessage(role: .user, text: "summarize"),
        ])
        XCTAssertTrue(prompt.hasPrefix("[context]\nPage: Example"))
        XCTAssertTrue(prompt.hasSuffix("User: summarize"))
    }

    func testEmptyConversationIsEmptyPrompt() {
        XCTAssertEqual(HermesClient.prompt(from: []), "")
    }

    /// A path that doesn't exist must not be reported as configured — the menu items and palette
    /// commands hide on this.
    func testIsConfiguredRejectsMissingBinary() {
        let saved = HermesSettings.binaryPath
        defer { HermesSettings.binaryPath = saved }
        HermesSettings.binaryPath = "/nonexistent/hermes"
        XCTAssertFalse(HermesSettings.isConfigured)
    }
}
