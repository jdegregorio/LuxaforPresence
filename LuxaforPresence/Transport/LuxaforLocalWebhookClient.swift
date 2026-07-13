import Foundation
import OSLog

final class LuxaforLocalWebhookClient: LuxaforClientProtocol {
    private let baseURL: URL
    private let token: String
    private let logger = Logger(subsystem: "com.example.LuxaforPresence", category: "LuxaforLocalWebhookClient")
    private let sender: LatestWinsRequestSender

    init(baseURL: String, token: String, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.baseURL = URL(string: baseURL)?.standardized ?? URL(string: "http://127.0.0.1:5383")!
        self.token = token
        self.sender = LatestWinsRequestSender(session: session, logger: logger)
    }

    func turnOnRed(userId: String) {
        postColor(.red)
    }

    func turnOnYellow(userId: String) {
        postColor(.orange)
    }

    func turnOff(userId: String) {
        postColor(.off)
    }

    private func postColor(_ color: LuxaforColor) {
        guard let url = URL(string: "color", relativeTo: baseURL) else {
            logger.error("Failed to build local webhook URL for color endpoint")
            return
        }
        sender.send(identifier: color.hex, actionDescription: color.localHex) { [token] in
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["color": color.localHex])
            return request
        }
    }
}
