import Foundation
import Testing
@testable import PaneCore

struct FileWatcherTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var file: URL { directory.appendingPathComponent("pane/settings.json") }

    private func change(
        to file: URL, within timeout: Duration = .seconds(5), after action: @Sendable @escaping () throws -> Void
    ) async throws -> Bool {
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self)
        let watcher = FileWatcher(files: [file], queue: .global()) { continuation.yield() }
        try await Task.sleep(for: .milliseconds(300))
        try action()
        let giveUp = Task {
            try await Task.sleep(for: timeout)
            continuation.finish()
        }
        defer { giveUp.cancel() }
        var iterator = changes.makeAsyncIterator()
        let changed: Void? = await iterator.next()
        withExtendedLifetime(watcher) {}
        return changed != nil
    }

    private func write(_ text: String, to url: URL, atomically: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: atomically ? .atomic : [])
    }

    @Test func reportsAFileReplacedAtomically() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try write("{}", to: file)
        let file = file
        #expect(try await change(to: file) { try Data("{ }".utf8).write(to: file, options: .atomic) })
    }

    @Test func reportsAFileInADirectoryCreatedLater() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = file
        #expect(try await change(to: file) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: file)
        })
    }

    @Test func reportsADirectoryReplacedByASymlink() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let elsewhere = directory.appendingPathComponent("dotfiles/pane")
        try write("{}", to: elsewhere.appendingPathComponent("settings.json"))
        let file = file
        #expect(try await change(to: file) {
            try FileManager.default.createSymbolicLink(at: file.deletingLastPathComponent(), withDestinationURL: elsewhere)
        })
    }

    @Test func ignoresOtherFilesBesideTheWatchedOne() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try write("{}", to: file)
        let file = file
        #expect(try await !change(to: file, within: .seconds(1)) {
            let folder = file.deletingLastPathComponent()
            try Data("{}".utf8).write(to: folder.appendingPathComponent("other.json"))
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: folder.appendingPathComponent("nested/settings.json"))
        })
    }
}
