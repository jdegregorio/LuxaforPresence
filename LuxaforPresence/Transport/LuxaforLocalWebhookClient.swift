import Foundation
import OSLog

final class LuxaforLocalWebhookClient: LuxaforClientProtocol {
    private let endpoint: LocalWebhookEndpoint
    private let token: String
    private let logger = Logger(subsystem: "com.example.LuxaforPresence", category: "LuxaforLocalWebhookClient")
    private let sender: LatestWinsRequestSender

    convenience init(
        baseURL: String,
        token: String,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) throws {
        let endpoint = try LocalWebhookEndpoint(validating: baseURL)
        self.init(endpoint: endpoint, token: token, session: session)
    }

    init(
        endpoint: LocalWebhookEndpoint,
        token: String,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.endpoint = endpoint
        self.token = token
        self.sender = LatestWinsRequestSender(session: session, logger: logger)
    }

    func setSolidColor(_ color: LuxaforColor, userId: String, force: Bool) {
        let url = endpoint.colorURL
        logger.debug("Sending local webhook color \(color.localHex, privacy: .public) to configured endpoint")
        sender.send(
            identifier: color.hex,
            actionDescription: color.localHex,
            force: force
        ) { [token] in
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["color": color.localHex])
            return request
        }
    }
}
