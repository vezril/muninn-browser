import XCTest
@testable import Muninn

/// Web Store install helpers: extension-id parsing + CRX→ZIP header stripping.
@MainActor
final class ExtensionInstallTests: XCTestCase {

    func testExtensionIDFromBareID() {
        let id = "ghmbeldphafepmbegfdlkpapadhbakde"
        XCTAssertEqual(ExtensionManager.extensionID(from: id), id)
        XCTAssertEqual(ExtensionManager.extensionID(from: "  \(id)\n"), id)
    }

    func testExtensionIDFromStoreURLs() {
        let id = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        XCTAssertEqual(ExtensionManager.extensionID(from: "https://chromewebstore.google.com/detail/ublock-origin-lite/\(id)"), id)
        XCTAssertEqual(ExtensionManager.extensionID(from: "https://chrome.google.com/webstore/detail/foo/\(id)?hl=en"), id)
    }

    func testExtensionIDRejectsNonIDs() {
        XCTAssertNil(ExtensionManager.extensionID(from: "https://example.com/not-an-extension"))
        XCTAssertNil(ExtensionManager.extensionID(from: "hello"))
        XCTAssertNil(ExtensionManager.extensionID(from: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")) // out of a–p range
    }

    func testZipDataStripsCRX3Header() {
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0xDE, 0xAD]) // "PK\3\4" + payload
        let header = Data([1, 2, 3, 4, 5])                    // arbitrary 5-byte protobuf header
        var crx = Data("Cr24".utf8)
        crx.append(contentsOf: [3, 0, 0, 0])                                          // version 3 (LE)
        crx.append(contentsOf: [UInt8(header.count), 0, 0, 0])                        // header length (LE)
        crx.append(header)
        crx.append(zip)
        XCTAssertEqual(ExtensionManager.zipData(fromCRX: crx), zip)
    }

    func testZipDataPassesThroughNonCRX() {
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x01, 0x02])
        XCTAssertEqual(ExtensionManager.zipData(fromCRX: zip), zip)
    }
}
