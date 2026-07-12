import XCTest
@testable import LuxaforPresence

final class LuxaforClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func test_turnOnRed_sendsExpectedRemotePayload() throws {
        let requestReceived = expectation(description: "red request received")
        TestURLProtocol.handler = { request, protocolInstance in
            XCTAssertEqual(request.url?.absoluteString, "https://api.luxafor.com/webhook/v1/actions/solid_color")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let payload = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(payload["userId"] as? String, "test-user")
            let fields = try XCTUnwrap(payload["actionFields"] as? [String: Any])
            XCTAssertEqual(fields["color"] as? String, "custom")
            XCTAssertEqual(fields["custom_color"] as? String, "FF0000")

            protocolInstance.respond(statusCode: 200)
            requestReceived.fulfill()
        }

        let client = LuxaforClient(session: makeSession())
        client.turnOnRed(userId: "test-user")

        wait(for: [requestReceived], timeout: 2)
    }

    func test_turnOff_sendsExpectedRemotePayload() throws {
        let requestReceived = expectation(description: "off request received")
        TestURLProtocol.handler = { request, protocolInstance in
            let payload = try XCTUnwrap(Self.jsonBody(from: request))
            let fields = try XCTUnwrap(payload["actionFields"] as? [String: Any])
            XCTAssertEqual(fields["color"] as? String, "custom")
            XCTAssertEqual(fields["custom_color"] as? String, "000000")

            protocolInstance.respond(statusCode: 200)
            requestReceived.fulfill()
        }

        let client = LuxaforClient(session: makeSession())
        client.turnOff(userId: "test-user")

        wait(for: [requestReceived], timeout: 2)
    }

    func test_transientFailure_retriesLatestStateUntilConfirmed() {
        let requestConfirmed = expectation(description: "retry succeeded")
        let lock = NSLock()
        var requestCount = 0
        TestURLProtocol.handler = { _, protocolInstance in
            lock.lock()
            requestCount += 1
            let currentCount = requestCount
            lock.unlock()

            if currentCount == 1 {
                protocolInstance.respond(statusCode: 503)
            } else {
                protocolInstance.respond(statusCode: 200)
                requestConfirmed.fulfill()
            }
        }

        let client = LuxaforClient(session: makeSession())
        client.turnOnRed(userId: "test-user")

        wait(for: [requestConfirmed], timeout: 2)
        lock.lock()
        let finalCount = requestCount
        lock.unlock()
        XCTAssertEqual(finalCount, 2)
    }

    func test_confirmedDuplicateState_isNotSentAgain() {
        let firstRequestConfirmed = expectation(description: "first request confirmed")
        let duplicateRequest = expectation(description: "duplicate request sent")
        duplicateRequest.isInverted = true
        let lock = NSLock()
        var requestCount = 0
        TestURLProtocol.handler = { _, protocolInstance in
            lock.lock()
            requestCount += 1
            let currentCount = requestCount
            lock.unlock()

            protocolInstance.respond(statusCode: 200)
            if currentCount == 1 {
                firstRequestConfirmed.fulfill()
            } else {
                duplicateRequest.fulfill()
            }
        }

        let client = LuxaforClient(session: makeSession())
        client.turnOff(userId: "test-user")
        wait(for: [firstRequestConfirmed], timeout: 2)
        client.turnOff(userId: "test-user")

        wait(for: [duplicateRequest], timeout: 0.5)
        lock.lock()
        let finalCount = requestCount
        lock.unlock()
        XCTAssertEqual(finalCount, 1)
    }

    func test_supersededFailure_doesNotRetryStaleState() {
        let redStarted = expectation(description: "red request started")
        let offConfirmed = expectation(description: "off request confirmed")
        let staleRetry = expectation(description: "stale red request retried")
        staleRetry.isInverted = true
        let releaseRed = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var requestCount = 0

        TestURLProtocol.handler = { request, protocolInstance in
            lock.lock()
            requestCount += 1
            let currentCount = requestCount
            lock.unlock()

            guard let fields = Self.actionFields(from: request),
                  let color = fields["custom_color"] as? String else {
                XCTFail("Missing custom color")
                protocolInstance.respond(statusCode: 400)
                return
            }

            if color == "FF0000" && currentCount == 1 {
                redStarted.fulfill()
                _ = releaseRed.wait(timeout: .now() + 2)
                protocolInstance.respond(statusCode: 503)
            } else if color == "000000" {
                protocolInstance.respond(statusCode: 200)
                offConfirmed.fulfill()
            } else {
                protocolInstance.respond(statusCode: 200)
                staleRetry.fulfill()
            }
        }

        let client = LuxaforClient(session: makeSession())
        client.turnOnRed(userId: "test-user")
        wait(for: [redStarted], timeout: 2)
        client.turnOff(userId: "test-user")
        wait(for: [offConfirmed], timeout: 2)
        releaseRed.signal()

        wait(for: [staleRetry], timeout: 0.5)
        lock.lock()
        let finalCount = requestCount
        lock.unlock()
        XCTAssertEqual(finalCount, 2)
    }

    func test_localClient_sendsTokenAndColorToLocalEndpoint() throws {
        let requestReceived = expectation(description: "local request received")
        TestURLProtocol.handler = { request, protocolInstance in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:5383/color")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let payload = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(payload["color"] as? String, "#FF7000")
            protocolInstance.respond(statusCode: 200)
            requestReceived.fulfill()
        }

        let client = LuxaforLocalWebhookClient(
            baseURL: "http://127.0.0.1:5383",
            token: "test-token",
            session: makeSession()
        )
        client.turnOnYellow(userId: "ignored")

        wait(for: [requestReceived], timeout: 2)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonBody(from request: URLRequest) -> [String: Any]? {
        guard let body = request.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func actionFields(from request: URLRequest) -> [String: Any]? {
        jsonBody(from: request)?["actionFields"] as? [String: Any]
    }
}

private final class TestURLProtocol: URLProtocol {
    static var handler: ((URLRequest, TestURLProtocol) throws -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            try handler(request, self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    func respond(statusCode: Int) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}
