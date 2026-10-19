import CoreServices
import Foundation

/// Follows folder changes with FSEvents and reports the folders that changed.
final class FSWatcher {
    /// `changed`: folders whose entries changed. `deep`: folders to read again in full (macOS dropped events
    /// for them). `rootChanged`: a watched folder itself moved or disappeared.
    typealias Handler = (_ changed: [String], _ deep: [String], _ rootChanged: Bool) -> Void

    private let paths: [String]
    private let handler: Handler
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "app.haven.fsevents", qos: .utility)

    init(paths: [String], handler: @escaping Handler) {
        self.paths = paths
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            guard let list = cfArray as? [String] else { return }
            var dirs: [String] = []
            var deep: [String] = []
            var rootChanged = false
            for i in 0..<min(count, list.count) {
                let flags = eventFlags[i]
                if flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
                    rootChanged = true
                } else if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
                    deep.append(list[i])
                } else {
                    dirs.append(list[i])
                }
            }
            watcher.handler(dirs, deep, rootChanged)
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }
}
