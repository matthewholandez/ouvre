import Foundation

public struct Destination: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleID + "|" + (profileDirectory ?? "") }
    public var bundleID: String
    public var browserName: String
    public var profileDirectory: String?
    public var profileName: String?

    public init(bundleID: String, browserName: String, profileDirectory: String? = nil, profileName: String? = nil) {
        self.bundleID = bundleID
        self.browserName = browserName
        self.profileDirectory = profileDirectory
        self.profileName = profileName
    }

    public var displayName: String {
        guard let profileName else { return browserName }
        return "\(browserName) · \(profileName)"
    }
}

public enum RulePattern: String, Codable, CaseIterable, Sendable {
    case exactDomain
    case domainAndSubdomains
    case urlPrefix

    public var label: String {
        switch self {
        case .exactDomain: "Exact domain"
        case .domainAndSubdomains: "Domain and subdomains"
        case .urlPrefix: "URL prefix"
        }
    }
}

public enum RuleAction: Codable, Hashable, Sendable {
    case picker
    case destination(Destination)
}

public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var pattern: RulePattern
    public var value: String
    public var action: RuleAction

    public init(id: UUID = UUID(), isEnabled: Bool = true, pattern: RulePattern, value: String, action: RuleAction) {
        self.id = id
        self.isEnabled = isEnabled
        self.pattern = pattern
        self.value = value
        self.action = action
    }
}

public struct Configuration: Codable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var rules: [Rule]
    public var hiddenDestinationIDs: Set<String>
    public var fallback: Destination?

    public init(version: Int = Configuration.currentVersion, rules: [Rule] = [], hiddenDestinationIDs: Set<String> = [], fallback: Destination? = nil) {
        self.version = version
        self.rules = rules
        self.hiddenDestinationIDs = hiddenDestinationIDs
        self.fallback = fallback
    }
}

public enum RoutingDecision: Equatable, Sendable {
    case picker
    case destination(Destination)
}

public enum Routing {
    public static func decision(for url: URL, configuration: Configuration) -> RoutingDecision {
        for rule in configuration.rules where rule.isEnabled {
            if matches(rule, url: url) {
                switch rule.action {
                case .picker: return .picker
                case .destination(let destination): return .destination(destination)
                }
            }
        }
        return configuration.fallback.map(RoutingDecision.destination) ?? .picker
    }

    public static func matches(_ rule: Rule, url: URL) -> Bool {
        guard isWebURL(url), let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return false }
        let input = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rule.pattern {
        case .exactDomain:
            guard let domain = normalizedDomain(input) else { return false }
            return host == domain
        case .domainAndSubdomains:
            guard let domain = normalizedDomain(input) else { return false }
            return host == domain || host.hasSuffix("." + domain)
        case .urlPrefix:
            guard let prefix = URLComponents(string: input),
                  let scheme = prefix.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let prefixHost = prefix.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), !prefixHost.isEmpty, prefixHost == host,
                  prefix.user == nil, prefix.password == nil, prefix.fragment == nil,
                  let candidate = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  candidate.scheme?.lowercased() == scheme,
                  (prefix.port ?? defaultPort(for: scheme)) == (candidate.port ?? defaultPort(for: scheme))
            else { return false }
            let prefixPath = prefix.percentEncodedPath.isEmpty ? "/" : prefix.percentEncodedPath
            let candidatePath = candidate.percentEncodedPath.isEmpty ? "/" : candidate.percentEncodedPath
            if let query = prefix.percentEncodedQuery {
                return candidatePath == prefixPath && candidate.percentEncodedQuery?.hasPrefix(query) == true
            }
            guard candidatePath.hasPrefix(prefixPath) else { return false }
            return true
        }
    }

    public static func validationError(pattern: RulePattern, value: String) -> String? {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch pattern {
        case .exactDomain, .domainAndSubdomains:
            return normalizedDomain(input) == nil ? "Enter a domain such as example.com." : nil
        case .urlPrefix:
            guard let url = URLComponents(string: input),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil else {
                return "Enter a full http:// or https:// URL without credentials or a fragment."
            }
            return nil
        }
    }

    public static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && !(url.host ?? "").isEmpty
    }

    private static func normalizedDomain(_ value: String) -> String? {
        let domain = value.lowercased().hasSuffix(".") ? String(value.lowercased().dropLast()) : value.lowercased()
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !domain.isEmpty, labels.allSatisfy({ label in
            !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-") &&
            label.unicodeScalars.allSatisfy { allowed.contains($0) }
        }) else { return nil }
        return domain
    }

    private static func defaultPort(for scheme: String) -> Int { scheme == "https" ? 443 : 80 }
}
