import Foundation

public struct Settings: Codable, Equatable {
    public var model: String
    public var endpoint: URL
    public var timeoutSeconds: Double

    public init(model: String, endpoint: URL, timeoutSeconds: Double) {
        self.model = model
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
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
        case model, endpoint, timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.defaults
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        endpoint = try c.decodeIfPresent(URL.self, forKey: .endpoint) ?? d.endpoint
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? d.timeoutSeconds
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
