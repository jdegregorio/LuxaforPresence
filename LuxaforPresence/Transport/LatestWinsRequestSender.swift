import Foundation
import OSLog

/// Delivers only the most recently requested state and keeps retrying transient
/// failures until that state is confirmed or superseded.
final class LatestWinsRequestSender {
    typealias RequestFactory = () throws -> URLRequest

    private struct DesiredRequest {
        let identifier: String
        let actionDescription: String
        let requestFactory: RequestFactory
    }

    private let session: URLSession
    private let logger: Logger
    private let queue = DispatchQueue(label: "com.example.LuxaforPresence.webhook-delivery")

    private var generation: UInt64 = 0
    private var desiredRequest: DesiredRequest?
    private var confirmedIdentifier: String?
    private var inFlightTask: URLSessionDataTask?
    private var retryScheduled = false

    init(session: URLSession, logger: Logger) {
        self.session = session
        self.logger = logger
    }

    func send(
        identifier: String,
        actionDescription: String,
        requestFactory: @escaping RequestFactory
    ) {
        queue.async {
            if self.desiredRequest?.identifier == identifier,
               self.inFlightTask != nil || self.retryScheduled || self.confirmedIdentifier == identifier {
                self.logger.debug("Coalescing duplicate webhook state \(actionDescription, privacy: .public)")
                return
            }

            self.generation &+= 1
            let generation = self.generation
            self.desiredRequest = DesiredRequest(
                identifier: identifier,
                actionDescription: actionDescription,
                requestFactory: requestFactory
            )
            self.retryScheduled = false
            guard self.inFlightTask == nil else {
                self.logger.debug(
                    "Queued webhook state \(actionDescription, privacy: .public) behind the in-flight request"
                )
                return
            }
            self.perform(
                generation: generation,
                identifier: identifier,
                actionDescription: actionDescription,
                attempt: 1,
                requestFactory: requestFactory
            )
        }
    }

    private func perform(
        generation: UInt64,
        identifier: String,
        actionDescription: String,
        attempt: Int,
        requestFactory: @escaping RequestFactory
    ) {
        guard generation == self.generation, desiredRequest?.identifier == identifier else { return }

        let request: URLRequest
        do {
            request = try requestFactory()
        } catch {
            logger.error(
                "Failed to build webhook request for \(actionDescription, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        logger.debug(
            "Sending latest webhook state \(actionDescription, privacy: .public), attempt \(attempt, privacy: .public)"
        )
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            self.queue.async {
                self.handleResult(
                    generation: generation,
                    identifier: identifier,
                    actionDescription: actionDescription,
                    attempt: attempt,
                    requestFactory: requestFactory,
                    response: response,
                    error: error
                )
            }
        }
        inFlightTask = task
        task.resume()
    }

    private func handleResult(
        generation: UInt64,
        identifier: String,
        actionDescription: String,
        attempt: Int,
        requestFactory: @escaping RequestFactory,
        response: URLResponse?,
        error: Error?
    ) {
        inFlightTask = nil
        guard generation == self.generation, desiredRequest?.identifier == identifier else {
            logger.debug("Completed superseded webhook state \(actionDescription, privacy: .public); sending the queued state")
            sendCurrentDesiredState()
            return
        }

        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode),
           error == nil {
            confirmedIdentifier = identifier
            logger.debug("Confirmed webhook state \(actionDescription, privacy: .public)")
            return
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard shouldRetry(statusCode: statusCode, error: error) else {
            if let statusCode {
                logger.error(
                    "Webhook rejected state \(actionDescription, privacy: .public) with non-retryable status \(statusCode, privacy: .public)"
                )
            } else {
                logger.error("Webhook returned no HTTP response for state \(actionDescription, privacy: .public)")
            }
            return
        }

        let delay = retryDelaySeconds(afterAttempt: attempt)
        retryScheduled = true
        if let error {
            logger.error(
                "Webhook state \(actionDescription, privacy: .public) failed: \(error.localizedDescription, privacy: .public); retrying in \(delay, privacy: .public)s"
            )
        } else if let statusCode {
            logger.error(
                "Webhook state \(actionDescription, privacy: .public) returned \(statusCode, privacy: .public); retrying in \(delay, privacy: .public)s"
            )
        }

        queue.asyncAfter(deadline: .now() + delay) {
            guard generation == self.generation, self.desiredRequest?.identifier == identifier else { return }
            self.retryScheduled = false
            self.perform(
                generation: generation,
                identifier: identifier,
                actionDescription: actionDescription,
                attempt: attempt + 1,
                requestFactory: requestFactory
            )
        }
    }

    private func sendCurrentDesiredState() {
        guard inFlightTask == nil, let desiredRequest else { return }
        retryScheduled = false
        perform(
            generation: generation,
            identifier: desiredRequest.identifier,
            actionDescription: desiredRequest.actionDescription,
            attempt: 1,
            requestFactory: desiredRequest.requestFactory
        )
    }

    private func shouldRetry(statusCode: Int?, error: Error?) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return false
        }
        if error != nil || statusCode == nil {
            return true
        }
        guard let statusCode else { return true }
        return statusCode == 408 || statusCode == 425 || statusCode == 429 || (500..<600).contains(statusCode)
    }

    private func retryDelaySeconds(afterAttempt attempt: Int) -> TimeInterval {
        switch attempt {
        case 1: return 0.2
        case 2: return 0.5
        case 3: return 1
        case 4: return 2
        case 5: return 5
        case 6: return 15
        default: return 30
        }
    }
}
