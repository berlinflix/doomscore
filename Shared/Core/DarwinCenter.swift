import Foundation

/// Cross-process pings between the app, widgets, intents and the broadcast
/// extension. Darwin notifications carry no payload — receivers re-read the
/// shared files.
enum DarwinName {
    private static var prefix: String { AppEnvironment.appGroupID }
    static var liveChanged: String { "\(prefix).live-changed" }
    static var broadcastStarted: String { "\(prefix).broadcast-started" }
    static var broadcastFinished: String { "\(prefix).broadcast-finished" }
    static var settingsChanged: String { "\(prefix).settings-changed" }
    static var hintChanged: String { "\(prefix).hint-changed" }
    static var stopRequested: String { "\(prefix).stop-requested" }
    static var dataReset: String { "\(prefix).data-reset" }
    static var screenTimeChanged: String { "\(prefix).screen-time-changed" }
}

final class DarwinCenter: @unchecked Sendable {
    static let shared = DarwinCenter()

    private let lock = NSLock()
    private var handlers: [String: [UUID: () -> Void]] = [:]
    private var registered: Set<String> = []

    private var center: CFNotificationCenter { CFNotificationCenterGetDarwinNotifyCenter() }

    func post(_ name: String) {
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Handlers run on an arbitrary thread — hop to your own queue/actor.
    @discardableResult
    func observe(_ name: String, handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        handlers[name, default: [:]][id] = handler
        let needsRegistration = registered.insert(name).inserted
        lock.unlock()

        if needsRegistration {
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(center, observer, { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let me = Unmanaged<DarwinCenter>.fromOpaque(observer).takeUnretainedValue()
                me.fire(name.rawValue as String)
            }, name as CFString, nil, .deliverImmediately)
        }
        return id
    }

    func remove(_ id: UUID) {
        lock.lock()
        for key in handlers.keys { handlers[key]?[id] = nil }
        lock.unlock()
    }

    private func fire(_ name: String) {
        lock.lock()
        let callbacks = handlers[name].map { Array($0.values) } ?? []
        lock.unlock()
        callbacks.forEach { $0() }
    }
}
