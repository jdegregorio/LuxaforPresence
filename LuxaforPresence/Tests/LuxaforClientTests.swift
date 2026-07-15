import XCTest
@testable import LuxaforPresence

final class LuxaforClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func test_setSolidRed_sendsExpectedRemotePayload() throws {
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
        client.setSolidColor(.red, userId: "test-user", force: false)

        wait(for: [requestReceived], timeout: 2)
    }

    func test_setSolidOff_sendsExpectedRemotePayload() throws {
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
        client.setSolidColor(.off, userId: "test-user", force: false)

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
        client.setSolidColor(.red, userId: "test-user", force: false)

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
        client.setSolidColor(.off, userId: "test-user", force: false)
        wait(for: [firstRequestConfirmed], timeout: 2)
        client.setSolidColor(.off, userId: "test-user", force: false)

        wait(for: [duplicateRequest], timeout: 0.5)
        lock.lock()
        let finalCount = requestCount
        lock.unlock()
        XCTAssertEqual(finalCount, 1)
    }

    func test_sameColorForDifferentRemoteUsers_isSentForEachUser() {
        let requestsReceived = expectation(description: "both users received requests")
        requestsReceived.expectedFulfillmentCount = 2
        let lock = NSLock()
        var receivedUserIds: [String] = []
        TestURLProtocol.handler = { request, protocolInstance in
            let payload = try XCTUnwrap(Self.jsonBody(from: request))
            let userId = try XCTUnwrap(payload["userId"] as? String)
            lock.lock()
            receivedUserIds.append(userId)
            lock.unlock()
            protocolInstance.respond(statusCode: 200)
            requestsReceived.fulfill()
        }

        let client = LuxaforClient(session: makeSession())
        client.setSolidColor(.red, userId: "first-user", force: false)
        client.setSolidColor(.red, userId: "second-user", force: false)

        wait(for: [requestsReceived], timeout: 2)
        lock.lock()
        let finalUserIds = receivedUserIds
        lock.unlock()
        XCTAssertEqual(finalUserIds, ["first-user", "second-user"])
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
        client.setSolidColor(.red, userId: "test-user", force: false)
        wait(for: [redStarted], timeout: 2)
        client.setSolidColor(.off, userId: "test-user", force: false)
        releaseRed.signal()
        wait(for: [offConfirmed], timeout: 2)

        wait(for: [staleRetry], timeout: 0.5)
        lock.lock()
        let finalCount = requestCount
        lock.unlock()
        XCTAssertEqual(finalCount, 2)
    }

    func test_localClient_sendsTokenAndColorToLocalEndpoint() throws {
        let requestReceived = expectation(description: "local request received")
        TestURLProtocol.handler = { request, protocolInstance in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:5383/luxafor/v1/color")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Connection"), "close")
            let payload = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(payload["color"] as? String, "#FFFF00")
            protocolInstance.respond(statusCode: 200)
            requestReceived.fulfill()
        }

        let client = try LuxaforLocalWebhookClient(
            baseURL: "http://127.0.0.1:5383/luxafor/v1",
            token: "test-token",
            session: makeSession()
        )
        client.setSolidColor(.yellow, userId: "ignored", force: false)

        wait(for: [requestReceived], timeout: 2)
    }

    func test_localClient_usesFreshSessionForEachSemanticRequest() throws {
        let firstRequestStarted = expectation(description: "first local request started")
        let secondRequestConfirmed = expectation(description: "second local request confirmed")
        let releaseFirstRequest = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var requestCount = 0
        var sessionCount = 0
        TestURLProtocol.handler = { _, protocolInstance in
            lock.lock()
            requestCount += 1
            let currentRequest = requestCount
            lock.unlock()

            if currentRequest == 1 {
                firstRequestStarted.fulfill()
                _ = releaseFirstRequest.wait(timeout: .now() + 2)
            }
            protocolInstance.respond(statusCode: 200)
            if currentRequest == 2 {
                secondRequestConfirmed.fulfill()
            }
        }

        let client = LuxaforLocalWebhookClient(
            endpoint: try LocalWebhookEndpoint(validating: "http://127.0.0.1:5383"),
            token: "test-token",
            sessionFactory: { [unowned self] in
                lock.lock()
                sessionCount += 1
                lock.unlock()
                return self.makeSession()
            }
        )
        client.setSolidColor(.purple, userId: "ignored", force: false)
        wait(for: [firstRequestStarted], timeout: 2)
        client.setSolidColor(.yellow, userId: "ignored", force: false)
        releaseFirstRequest.signal()

        wait(for: [secondRequestConfirmed], timeout: 2)
        lock.lock()
        let finalSessionCount = sessionCount
        lock.unlock()
        XCTAssertEqual(finalSessionCount, 2)
    }

    func test_localSessionConfiguration_limitsAndReusesOneConnection() {
        let configuration = LocalWebhookSession.makeConfiguration()

        XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 1)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.urlCache)
    }

    func test_localServiceHTTPProbe_usesHeadAndAcceptsAnyHTTPResponse() throws {
        let requestReceived = expectation(description: "health request received")
        let completionReceived = expectation(description: "health completion received")
        TestURLProtocol.handler = { request, protocolInstance in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:5383/base/color")
            XCTAssertEqual(request.httpMethod, "HEAD")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Connection"), "keep-alive")
            protocolInstance.respond(statusCode: 503)
            requestReceived.fulfill()
        }
        let probe = LocalServiceHTTPProbe(
            endpoint: try LocalWebhookEndpoint(validating: "http://127.0.0.1:5383/base"),
            session: makeSession()
        )

        probe.probe { reachable in
            XCTAssertTrue(reachable)
            completionReceived.fulfill()
        }

        wait(for: [requestReceived, completionReceived], timeout: 2)
    }

    func test_localServiceHTTPProbe_reportsTransportFailure() throws {
        let completionReceived = expectation(description: "health failure received")
        TestURLProtocol.handler = { _, _ in
            throw URLError(.cannotConnectToHost)
        }
        let probe = LocalServiceHTTPProbe(
            endpoint: try LocalWebhookEndpoint(validating: "http://127.0.0.1:5383"),
            session: makeSession()
        )

        probe.probe { reachable in
            XCTAssertFalse(reachable)
            completionReceived.fulfill()
        }

        wait(for: [completionReceived], timeout: 2)
    }

    func test_setSolidYellow_usesTrueYellowRemotePayload() throws {
        let requestReceived = expectation(description: "yellow request received")
        TestURLProtocol.handler = { request, protocolInstance in
            let fields = try XCTUnwrap(Self.actionFields(from: request))
            XCTAssertEqual(fields["color"] as? String, "custom")
            XCTAssertEqual(fields["custom_color"] as? String, "FFFF00")
            protocolInstance.respond(statusCode: 200)
            requestReceived.fulfill()
        }

        let client = LuxaforClient(session: makeSession())
        client.setSolidColor(.yellow, userId: "test-user", force: false)

        wait(for: [requestReceived], timeout: 2)
    }

    func test_outputBrightness_scalesLocalAndRemotePurplePayloads() throws {
        let requestsReceived = expectation(description: "scaled purple requests received")
        requestsReceived.expectedFulfillmentCount = 2
        let lock = NSLock()
        var payloadColors: [String] = []
        TestURLProtocol.handler = { request, protocolInstance in
            let color: String
            if request.url?.host == "api.luxafor.com" {
                color = try XCTUnwrap(Self.actionFields(from: request)?["custom_color"] as? String)
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Connection"), "close")
                color = try XCTUnwrap(Self.jsonBody(from: request)?["color"] as? String)
            }
            lock.lock()
            payloadColors.append(color)
            lock.unlock()
            protocolInstance.respond(statusCode: 200)
            requestsReceived.fulfill()
        }

        let remoteClient = LuxaforClient(
            session: makeSession(),
            outputBrightness: 0.7
        )
        let localClient = try LuxaforLocalWebhookClient(
            baseURL: "http://127.0.0.1:5383",
            token: "test-token",
            session: makeSession(),
            outputBrightness: 0.7
        )
        remoteClient.setSolidColor(.purple, userId: "test-user", force: false)
        localClient.setSolidColor(.purple, userId: "ignored", force: false)

        wait(for: [requestsReceived], timeout: 2)
        lock.lock()
        let finalColors = payloadColors
        lock.unlock()
        XCTAssertEqual(Set(finalColors), Set(["6140AC", "#6140AC"]))
    }

    func test_setSolidCustomColor_preservesExactRGBPayloads() throws {
        let requestsReceived = expectation(description: "custom requests received")
        requestsReceived.expectedFulfillmentCount = 2
        let lock = NSLock()
        var payloadColors: [String] = []
        TestURLProtocol.handler = { request, protocolInstance in
            let color: String
            if request.url?.host == "api.luxafor.com" {
                color = try XCTUnwrap(Self.actionFields(from: request)?["custom_color"] as? String)
            } else {
                color = try XCTUnwrap(Self.jsonBody(from: request)?["color"] as? String)
            }
            lock.lock()
            payloadColors.append(color)
            lock.unlock()
            protocolInstance.respond(statusCode: 200)
            requestsReceived.fulfill()
        }

        let color = LuxaforColor(red: 1, green: 35, blue: 255)
        let remoteClient = LuxaforClient(session: makeSession())
        let localClient = try LuxaforLocalWebhookClient(
            baseURL: "http://127.0.0.1:5383",
            token: "test-token",
            session: makeSession()
        )
        remoteClient.setSolidColor(color, userId: "test-user", force: false)
        localClient.setSolidColor(color, userId: "ignored", force: false)

        wait(for: [requestsReceived], timeout: 2)
        lock.lock()
        let finalColors = payloadColors
        lock.unlock()
        XCTAssertEqual(Set(finalColors), Set(["0123FF", "#0123FF"]))
    }

    func test_forcedConfirmedDuplicate_isSentAgain() {
        let requestsReceived = expectation(description: "initial and forced requests received")
        requestsReceived.expectedFulfillmentCount = 2
        let firstRequestReceived = expectation(description: "first request received")
        let lock = NSLock()
        var requestCount = 0
        TestURLProtocol.handler = { _, protocolInstance in
            lock.lock()
            requestCount += 1
            let currentCount = requestCount
            lock.unlock()
            protocolInstance.respond(statusCode: 200)
            if currentCount == 1 {
                firstRequestReceived.fulfill()
            }
            requestsReceived.fulfill()
        }

        let client = LuxaforClient(session: makeSession())
        client.setSolidColor(.red, userId: "test-user", force: false)
        wait(for: [firstRequestReceived], timeout: 2)
        client.setSolidColor(.red, userId: "test-user", force: true)

        wait(for: [requestsReceived], timeout: 2)
        lock.lock()
        let finalCount = requestCount
        lock.unlock()
        XCTAssertEqual(finalCount, 2)
    }

    func test_forcedInFlightDuplicate_isQueuedAsLatestReassertion() {
        let firstRequestStarted = expectation(description: "first request started")
        let secondRequestConfirmed = expectation(description: "forced request confirmed")
        let releaseFirstRequest = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var requestCount = 0
        TestURLProtocol.handler = { _, protocolInstance in
            lock.lock()
            requestCount += 1
            let currentCount = requestCount
            lock.unlock()
            if currentCount == 1 {
                firstRequestStarted.fulfill()
                _ = releaseFirstRequest.wait(timeout: .now() + 2)
            }
            protocolInstance.respond(statusCode: 200)
            if currentCount == 2 {
                secondRequestConfirmed.fulfill()
            }
        }

        let client = LuxaforClient(session: makeSession())
        client.setSolidColor(.off, userId: "test-user", force: false)
        wait(for: [firstRequestStarted], timeout: 2)
        client.setSolidColor(.off, userId: "test-user", force: true)
        releaseFirstRequest.signal()

        wait(for: [secondRequestConfirmed], timeout: 2)
        lock.lock()
        let finalCount = requestCount
        lock.unlock()
        XCTAssertEqual(finalCount, 2)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonBody(from request: URLRequest) -> [String: Any]? {
        guard let body = bodyData(from: request),
              let object = try? JSONSerialization.jsonObject(with: body) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                return body
            }
            body.append(buffer, count: bytesRead)
        }
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
