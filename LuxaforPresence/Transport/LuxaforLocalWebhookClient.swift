import Foundation
import OSLog

final class LuxaforLocalWebhookClient: LuxaforClientProtocol {
    private let endpoint: LocalWebhookEndpoint
    private let token: String
    private let logger = Logger(subsystem: "com.jdegregorio.LuxaforPresence", category: "LuxaforLocalWebhookClient")
    private let sender: LatestWinsRequestSender
    private let outputBrightness: Double

    convenience init(
        baseURL: String,
        token: String,
        session: URLSession = LocalWebhookSession.make(),
        outputBrightness: Double = 1
    ) throws {
        let endpoint = try LocalWebhookEndpoint(validating: baseURL)
        self.init(
            endpoint: endpoint,
            token: token,
            session: session,
            outputBrightness: outputBrightness
        )
    }

    init(
        endpoint: LocalWebhookEndpoint,
        token: String,
        session: URLSession = LocalWebhookSession.make(),
        outputBrightness: Double = 1
    ) {
        self.endpoint = endpoint
        self.token = token
        self.sender = LatestWinsRequestSender(session: session, logger: logger)
        self.outputBrightness = outputBrightness
    }

    func setSolidColor(_ color: LuxaforColor, userId: String, force: Bool) {
        let adjustedColor = color.applyingBrightness(outputBrightness)
        let url = endpoint.colorURL
        logger.debug("Sending local webhook color \(adjustedColor.localHex, privacy: .public) to configured endpoint")
        sender.send(
            identifier: adjustedColor.hex,
            actionDescription: adjustedColor.localHex,
            force: force
        ) { [token] in
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("close", forHTTPHeaderField: "Connection")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["color": adjustedColor.localHex]
            )
            return request
        }
    }
}
