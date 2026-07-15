import Foundation

/// Creates an HTTP session for Luxafor's loopback webhook.
///
/// The Luxafor desktop listener retains accepted sockets after callers
/// disconnect. The reachability probe keeps one connection alive. Each output
/// request uses an isolated session that is invalidated after its low-frequency
/// semantic state change completes.
enum LocalWebhookSession {
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }

    static func make() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }
}
