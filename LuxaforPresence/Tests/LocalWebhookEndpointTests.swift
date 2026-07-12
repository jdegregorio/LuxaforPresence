import XCTest
@testable import LuxaforPresence

final class LocalWebhookEndpointTests: XCTestCase {
    func test_colorURL_appendsEndpointWithoutDiscardingBasePath() throws {
        let endpoint = try LocalWebhookEndpoint(validating: "https://example.com/luxafor/v1")

        XCTAssertEqual(endpoint.colorURL.absoluteString, "https://example.com/luxafor/v1/color")
    }

    func test_init_acceptsHTTPForLoopbackHosts() {
        XCTAssertNoThrow(try LocalWebhookEndpoint(validating: "http://127.0.0.42:5383/base"))
        XCTAssertNoThrow(try LocalWebhookEndpoint(validating: "http://localhost:5383"))
        XCTAssertNoThrow(try LocalWebhookEndpoint(validating: "http://[::1]:5383"))
    }

    func test_init_rejectsHTTPForNonLoopbackHost() {
        XCTAssertThrowsError(try LocalWebhookEndpoint(validating: "http://example.com/api"))
    }

    func test_init_rejectsEmbeddedCredentials() {
        XCTAssertThrowsError(try LocalWebhookEndpoint(validating: "https://user:secret@example.com/api"))
    }

    func test_init_rejectsAmbiguousURLComponents() {
        let invalidValues = [
            "",
            "/relative/path",
            "ftp://localhost/api",
            "https://example.com/api?token=secret",
            "https://example.com/api#fragment",
            "https://example.com:65536/api",
        ]

        for value in invalidValues {
            XCTAssertThrowsError(try LocalWebhookEndpoint(validating: value), value)
        }
    }

    func test_clientInitializerRejectsInvalidBaseURL() {
        XCTAssertThrowsError(
            try LuxaforLocalWebhookClient(baseURL: "not a URL", token: "test")
        )
    }
}
