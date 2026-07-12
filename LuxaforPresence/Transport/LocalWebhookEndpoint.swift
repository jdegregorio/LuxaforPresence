import Foundation

struct LocalWebhookEndpoint: Equatable {
    enum ValidationError: LocalizedError {
        case empty
        case invalidURL
        case unsupportedScheme
        case missingHost
        case credentialsNotAllowed
        case queryOrFragmentNotAllowed
        case invalidPort
        case insecureNonLoopbackHost

        var errorDescription: String? {
            switch self {
            case .empty:
                return "localWebhookBaseUrl must not be empty"
            case .invalidURL:
                return "localWebhookBaseUrl must be a valid absolute URL"
            case .unsupportedScheme:
                return "localWebhookBaseUrl must use http or https"
            case .missingHost:
                return "localWebhookBaseUrl must include a host"
            case .credentialsNotAllowed:
                return "localWebhookBaseUrl must not contain embedded credentials"
            case .queryOrFragmentNotAllowed:
                return "localWebhookBaseUrl must not contain a query or fragment"
            case .invalidPort:
                return "localWebhookBaseUrl must use a port between 1 and 65535"
            case .insecureNonLoopbackHost:
                return "localWebhookBaseUrl must use https unless its host is loopback"
            }
        }
    }

    static let defaultBaseURLString = "http://127.0.0.1:5383"
    static let `default` = LocalWebhookEndpoint(
        validatedBaseURL: URL(string: defaultBaseURLString)!
    )

    let baseURL: URL

    init(validating value: String) throws {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw ValidationError.empty
        }
        guard var components = URLComponents(string: trimmedValue) else {
            throw ValidationError.invalidURL
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ValidationError.unsupportedScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw ValidationError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw ValidationError.credentialsNotAllowed
        }
        guard components.query == nil, components.fragment == nil else {
            throw ValidationError.queryOrFragmentNotAllowed
        }
        if let port = components.port, !(1...65_535).contains(port) {
            throw ValidationError.invalidPort
        }
        guard scheme == "https" || Self.isLoopback(host: host) else {
            throw ValidationError.insecureNonLoopbackHost
        }

        components.scheme = scheme
        guard let url = components.url, url.scheme != nil, url.host != nil else {
            throw ValidationError.invalidURL
        }
        baseURL = url
    }

    var colorURL: URL {
        baseURL.appendingPathComponent("color", isDirectory: false)
    }

    private init(validatedBaseURL: URL) {
        baseURL = validatedBaseURL
    }

    private static func isLoopback(host: String) -> Bool {
        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        if normalizedHost == "localhost" || normalizedHost.hasSuffix(".localhost") {
            return true
        }
        if normalizedHost == "::1" || normalizedHost == "0:0:0:0:0:0:0:1" {
            return true
        }

        let octets = normalizedHost.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.first == "127",
              octets.allSatisfy({ UInt8($0) != nil }) else {
            return false
        }
        return true
    }
}
