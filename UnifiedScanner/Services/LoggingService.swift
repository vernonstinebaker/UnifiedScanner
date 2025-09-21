import Foundation

// Concurrency-safe logging utility using an actor for mutable state isolation.
// Public API preserves previous static call pattern: LoggingService.debug("msg")
// without requiring callers to be async or use await.
// Level changes and log emission occur on an internal actor.
actor LoggingService {
    enum Level: Int, CaseIterable { case off = 0, error = 1, warn = 2, info = 3, debug = 4 }
    enum Category: String, CaseIterable, Identifiable, Codable { case general, discovery, ping, arp, bonjour, snapshot, fingerprint, vendor, classification
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .general: return "General"
            case .discovery: return "Discovery"
            case .ping: return "Ping"
            case .arp: return "ARP"
            case .bonjour: return "Bonjour"
            case .snapshot: return "Snapshot"
            case .fingerprint: return "Fingerprint"
            case .vendor: return "Vendor"
            case .classification: return "Classification"
            }
        }
    }

    static let shared = LoggingService()

    private var minimumLevel: Level = .info
    private var enabledCategories: Set<Category> = Set(Category.allCases)

    // MARK: - Instance (actor isolated)
    private func isEnabled(_ level: Level, category: Category) -> Bool {
        if minimumLevel == .off { return false }
        guard enabledCategories.contains(category) else { return false }
        return level.rawValue <= minimumLevel.rawValue
    }

    private func emit(_ level: Level, category: Category, _ message: @autoclosure @Sendable () -> String) {
        #if DEBUG
        guard isEnabled(level, category: category) else { return }
        let label: String
        switch level {
        case .off: label = "OFF"
        case .error: label = "ERROR"
        case .warn: label = "WARN"
        case .info: label = "INFO"
        case .debug: label = "DEBUG"
        }
        print("[Scan][\(label)][\(category.rawValue.uppercased())] \(message())")
        #endif
    }

    private func setLevel(_ new: Level) { minimumLevel = new }
    private func setCategories(_ categories: Set<Category>) { enabledCategories = categories.isEmpty ? [.general] : categories }

    // MARK: - Static Wrappers (nonisolated; fire-and-forget)
    // These spawn a Task to hop onto the actor. Side effects are asynchronous.
    static func setMinimumLevel(_ level: Level) {
        Task { await shared.setLevel(level) }
    }

    static func setEnabledCategories(_ categories: Set<Category>) {
        Task { await shared.setCategories(categories) }
    }

    static func debug(_ message: @autoclosure @escaping @Sendable () -> String, category: Category = .general) {
        #if DEBUG
        Task { await shared.emit(.debug, category: category, message()) }
        #endif
    }
    static func info(_ message: @autoclosure @escaping @Sendable () -> String, category: Category = .general) {
        #if DEBUG
        Task { await shared.emit(.info, category: category, message()) }
        #endif
    }
    static func warn(_ message: @autoclosure @escaping @Sendable () -> String, category: Category = .general) {
        #if DEBUG
        Task { await shared.emit(.warn, category: category, message()) }
        #endif
    }
    static func error(_ message: @autoclosure @escaping @Sendable () -> String, category: Category = .general) {
        #if DEBUG
        Task { await shared.emit(.error, category: category, message()) }
        #endif
    }

    // MARK: - Optional synchronous API (if ever needed by tests)
    // Callers can await these for deterministic ordering.
    static func setMinimumLevelSync(_ level: Level) async { await shared.setLevel(level) }
    static func debugSync(_ message: @autoclosure @Sendable () -> String, category: Category = .general) async { await shared.emit(.debug, category: category, message()) }
    static func infoSync(_ message: @autoclosure @Sendable () -> String, category: Category = .general) async { await shared.emit(.info, category: category, message()) }
    static func warnSync(_ message: @autoclosure @Sendable () -> String, category: Category = .general) async { await shared.emit(.warn, category: category, message()) }
    static func errorSync(_ message: @autoclosure @Sendable () -> String, category: Category = .general) async { await shared.emit(.error, category: category, message()) }
}
