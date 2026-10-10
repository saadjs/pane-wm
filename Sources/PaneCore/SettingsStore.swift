import Foundation

public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        let data = try Data(contentsOf: url)
        let configuration: Configuration
        do { configuration = try JSONDecoder().decode(Configuration.self, from: data) }
        catch let error as DecodingError { throw SettingsError.invalid(Self.describe(error)) }
        guard configuration.version == 1 else { throw SettingsError.unsupportedVersion }
        if let duplicate = configuration.duplicateApp { throw SettingsError.invalid(duplicate) }
        var result = configuration
        result.layout = configuration.layout.normalized
        return result
    }

    public func save(_ configuration: Configuration) throws {
        let target = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: target, options: .atomic)
    }

    private static func describe(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case .dataCorrupted(let found), .keyNotFound(_, let found), .typeMismatch(_, let found), .valueNotFound(_, let found):
            context = found
        @unknown default: return error.localizedDescription
        }
        var detail = context.debugDescription
        if case .keyNotFound(let key, _) = error { detail = "“\(key.stringValue)” is missing." }
        if let underlying = context.underlyingError as NSError?,
           let reason = underlying.userInfo[NSDebugDescriptionErrorKey] as? String {
            detail += " \(reason)"
        }
        let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return path.isEmpty ? detail : "\(path): \(detail)"
    }

    public enum SettingsError: LocalizedError, Equatable {
        case unsupportedVersion
        case invalid(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "These settings were saved by a newer version of Pane."
            case .invalid(let detail): detail
            }
        }
    }
}
