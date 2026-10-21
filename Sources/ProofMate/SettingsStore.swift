import Foundation
import ProofMateCore

/// Owns the live settings and writes every change to settings.json.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: Settings
    private let url: URL

    init(url: URL = Settings.defaultFileURL) {
        self.url = url
        settings = Self.loadOrCreate(at: url)
    }

    func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        do {
            try next.save(to: url)
        } catch {
            log.error("settings save failed: \(String(describing: error))")
        }
    }

    /// Writes defaults on first run so the file exists for people who prefer editing it.
    private static func loadOrCreate(at url: URL) -> Settings {
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try Settings.defaults.save(to: url)
            }
            return try Settings.load(from: url)
        } catch {
            log.error("settings load failed, using defaults: \(String(describing: error))")
            return .defaults
        }
    }
}
