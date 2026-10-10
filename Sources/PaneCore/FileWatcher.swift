import CoreServices
import Foundation

public final class FileWatcher {
    private final class Handler {
        let paths: [String]
        let onChange: @Sendable () -> Void

        init(paths: [String], onChange: @escaping @Sendable () -> Void) {
            self.paths = paths
            self.onChange = onChange
        }

        func concerns(_ path: String, flags: FSEventStreamEventFlags) -> Bool {
            let rescan = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
            if flags & FSEventStreamEventFlags(rescan) != 0 { return true }
            let changed = path.hasSuffix("/") ? String(path.dropLast()) : path
            return paths.contains { $0 == changed || $0.hasPrefix(changed + "/") }
        }
    }

    public let files: Set<URL>
    private var stream: FSEventStreamRef?

    public init(files: Set<URL>, queue: DispatchQueue = .main, onChange: @escaping @Sendable () -> Void) {
        self.files = files
        let paths = files.map(Self.canonicalPath)
        let handler = Handler(paths: paths, onChange: onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Handler>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Handler>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let directories = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        stream = withExtendedLifetime(handler) { FSEventStreamCreate(
            nil,
            { _, info, count, eventPaths, eventFlags, _ in
                guard let info else { return }
                let handler = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue()
                let changed = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                guard (0..<count).contains(where: { handler.concerns(String(cString: changed[$0]), flags: eventFlags[$0]) })
                else { return }
                handler.onChange()
            },
            &context, Array(directories) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) }
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    static func canonicalPath(_ file: URL) -> String {
        var existing = file.standardizedFileURL.deletingLastPathComponent()
        var missing = [file.lastPathComponent]
        while existing.path != "/" {
            if let real = realpath(existing.path, nil) {
                defer { free(real) }
                return missing.reduce(URL(filePath: String(cString: real), directoryHint: .isDirectory)) {
                    $0.appendingPathComponent($1)
                }.path
            }
            missing.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return file.path
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
