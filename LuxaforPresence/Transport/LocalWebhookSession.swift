import Foundation

/// Creates an HTTP session for Luxafor's loopback webhook.
///
/// The Luxafor desktop listener retains accepted sockets after callers
/// disconnect. The reachability probe keeps one connection alive, while output
/// requests explicitly close after each low-frequency semantic state change.
enum LocalWebhookSession {
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpShouldUsePipelining = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }

    static func make() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }
}
