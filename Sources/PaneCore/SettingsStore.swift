import Foundation

public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        guard configuration.version == 1 else { throw SettingsError.unsupportedVersion }
        var result = configuration
        result.layout = configuration.layout.normalized
        return result
    }

    public func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }

    public enum SettingsError: LocalizedError {
        case unsupportedVersion

        public var errorDescription: String? { "These settings were saved by a newer version of Pane." }
    }
}
