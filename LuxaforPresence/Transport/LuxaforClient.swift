import Foundation
import OSLog

protocol LuxaforClientProtocol {
    func setSolidColor(_ color: LuxaforColor, userId: String, force: Bool)
}

final class LuxaforClient: LuxaforClientProtocol {
    private let endpoint = URL(string: "https://api.luxafor.com/webhook/v1/actions/solid_color")!
    private let logger = Logger(subsystem: "com.jdegregorio.LuxaforPresence", category: "LuxaforClient")
    private let sender: LatestWinsRequestSender

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.sender = LatestWinsRequestSender(session: session, logger: logger)
    }

    func setSolidColor(_ color: LuxaforColor, userId: String, force: Bool) {
        let deliveryIdentifier = "\(userId)\u{0}\(color.hex)"
        sender.send(
            identifier: deliveryIdentifier,
            actionDescription: color.hex,
            force: force
        ) { [endpoint] in
            var request = URLRequest(url: endpoint, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: [
                    "userId": userId,
                    "actionFields": [
                        "color": "custom",
                        "custom_color": color.hex,
                    ],
                ]
            )
            return request
        }
    }
}
