import Foundation
import OSLog

protocol LuxaforClientProtocol {
    func turnOnRed(userId: String)
    func turnOnYellow(userId: String)
    func turnOff(userId: String)
}

final class LuxaforClient: LuxaforClientProtocol {
    private let endpoint = URL(string: "https://api.luxafor.com/webhook/v1/actions/solid_color")!
    private let logger = Logger(subsystem: "com.example.LuxaforPresence", category: "LuxaforClient")
    private let sender: LatestWinsRequestSender

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.sender = LatestWinsRequestSender(session: session, logger: logger)
    }

    func turnOnRed(userId: String) {
        post(color: .red, userId: userId)
    }

    func turnOnYellow(userId: String) {
        post(color: .orange, userId: userId)
    }

    func turnOff(userId: String) {
        post(color: .off, userId: userId)
    }

    private func post(color: LuxaforColor, userId: String) {
        let deliveryIdentifier = "\(userId)\u{0}\(color.hex)"
        sender.send(identifier: deliveryIdentifier, actionDescription: color.hex) { [endpoint] in
            var request = URLRequest(url: endpoint, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["userId": userId, "actionFields": color.remoteActionFields]
            )
            return request
        }
    }
}
