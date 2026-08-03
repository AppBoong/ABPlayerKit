import ABPlayerKit
import CryptoKit
import Foundation

enum ABCacheKey {
    private static let transientQueryNames: Set<String> = [
        "access_token",
        "auth",
        "authorization",
        "expires",
        "expiry",
        "key-pair-id",
        "policy",
        "sig",
        "signature",
        "token"
    ]

    static func derive(from source: ABMediaSource) -> String {
        let normalizedURL = normalize(source.url)
        let digest = SHA256.hash(data: Data(normalizedURL.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func normalize(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if (components.scheme == "http" && components.port == 80)
            || (components.scheme == "https" && components.port == 443) {
            components.port = nil
        }

        components.queryItems = components.queryItems?
            .filter { !isTransientQueryName($0.name) }
            .sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }

        return components.string ?? url.absoluteString
    }

    private static func isTransientQueryName(_ name: String) -> Bool {
        let normalizedName = name.lowercased()
        return transientQueryNames.contains(normalizedName)
            || normalizedName.hasPrefix("x-amz-")
            || normalizedName.hasPrefix("x-goog-")
    }
}
