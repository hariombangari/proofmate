import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var model: String
    public var endpoint: URL
    public var timeoutSeconds: Double
    public var hotkey: Hotkey
    public var hasCompletedOnboarding: Bool

    public init(
        model: String,
        endpoint: URL,
        timeoutSeconds: Double,
        hotkey: Hotkey = .defaultCheck,
        hasCompletedOnboarding: Bool = false
    ) {
        self.model = model
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
        self.hotkey = hotkey
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let defaults = Settings(
        model: "qwen3:8b",
        endpoint: URL(string: "http://localhost:11434")!,
        timeoutSeconds: 20
    )

    /// ~/Library/Application Support/ProofMate/settings.json
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProofMate", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private enum CodingKeys: String, CodingKey {
        case model, endpoint, timeoutSeconds, hotkey, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.defaults
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
            .flatMap(Settings.parseEndpoint) ?? d.endpoint
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? d.timeoutSeconds
        let decodedHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? d.hotkey
        hotkey = decodedHotkey.isValid ? decodedHotkey : d.hotkey
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? d.hasCompletedOnboarding
    }

    /// Accepts a bare http(s) base URL with a host, e.g. "http://localhost:11434". Trims whitespace.
    /// Rejects a path, query, fragment, or credentials: OllamaEngine appends "api/chat" to the
    /// endpoint, and credentials would be saved in plain text.
    public static func parseEndpoint(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.query == nil, parts.fragment == nil,
              parts.user == nil, parts.password == nil,
              parts.path.isEmpty || parts.path == "/" else { return nil }
        if let port = parts.port, !(1...65535).contains(port) { return nil }
        return url
    }

    /// Returns defaults when the file does not exist. Throws on unreadable or invalid JSON.
    public static func load(from url: URL) throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path) else { return defaults }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Settings.self, from: data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
