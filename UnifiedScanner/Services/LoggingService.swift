import Foundation

// Concurrency-safe logging utility using an actor for mutable state isolation.
// Public API preserves previous static call pattern: LoggingService.debug("msg")
// without requiring callers to be async or use await.
// Level changes and log emission occur on an internal actor.
actor LoggingService {
    enum Level: Int, CaseIterable { case off = 0, error = 1, warn = 2, info = 3, debug = 4 }

    static let shared = LoggingService()

    private var minimumLevel: Level = .info

    // MARK: - Instance (actor isolated)
    private func isEnabled(_ level: Level) -> Bool {
        if minimumLevel == .off { return false }
        return level.rawValue <= minimumLevel.rawValue
    }

    private func emit(_ level: Level, _ message: @autoclosure @Sendable () -> String) {
        #if DEBUG
        guard isEnabled(level) else { return }
        let label: String
        switch level {
        case .off: label = "OFF"
        case .error: label = "ERROR"
        case .warn: label = "WARN"
        case .info: label = "INFO"
        case .debug: label = "DEBUG"
        }
        print("[Scan][\(label)] \(message())")
        #endif
    }

    private func setLevel(_ new: Level) { minimumLevel = new }

    // MARK: - Static Wrappers (nonisolated; fire-and-forget)
    // These spawn a Task to hop onto the actor. Side effects are asynchronous.
    static func setMinimumLevel(_ level: Level) {
        Task { await shared.setLevel(level) }
    }

    static func debug(_ message: @autoclosure @escaping @Sendable () -> String) {
        #if DEBUG
        Task { await shared.emit(.debug, message()) }
        #endif
    }
    static func info(_ message: @autoclosure @escaping @Sendable () -> String) {
        #if DEBUG
        Task { await shared.emit(.info, message()) }
        #endif
    }
    static func warn(_ message: @autoclosure @escaping @Sendable () -> String) {
        #if DEBUG
        Task { await shared.emit(.warn, message()) }
        #endif
    }
    static func error(_ message: @autoclosure @escaping @Sendable () -> String) {
        #if DEBUG
        Task { await shared.emit(.error, message()) }
        #endif
    }

    // MARK: - Optional synchronous API (if ever needed by tests)
    // Callers can await these for deterministic ordering.
    static func setMinimumLevelSync(_ level: Level) async { await shared.setLevel(level) }
    static func debugSync(_ message: @autoclosure @Sendable () -> String) async { await shared.emit(.debug, message()) }
    static func infoSync(_ message: @autoclosure @Sendable () -> String) async { await shared.emit(.info, message()) }
    static func warnSync(_ message: @autoclosure @Sendable () -> String) async { await shared.emit(.warn, message()) }
    static func errorSync(_ message: @autoclosure @Sendable () -> String) async { await shared.emit(.error, message()) }
}
