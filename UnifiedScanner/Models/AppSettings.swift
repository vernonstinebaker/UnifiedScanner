import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    enum LoggingLevel: String, CaseIterable, Identifiable {
        case off, error, warn, info, debug
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .off: return "Off"
            case .error: return "Error"
            case .warn: return "Warn"
            case .info: return "Info"
            case .debug: return "Debug"
            }
        }
        var scanLoggerLevel: LoggingService.Level {
            switch self {
            case .off: return .off
            case .error: return .error
            case .warn: return .warn
            case .info: return .info
            case .debug: return .debug
            }
        }
    }

    @Published var loggingLevel: LoggingLevel {
        didSet {
            persist()
            LoggingService.setMinimumLevel(loggingLevel.scanLoggerLevel)
        }
    }

    @Published var enabledLogCategories: Set<LoggingService.Category> {
        didSet {
            if enabledLogCategories.isEmpty {
                enabledLogCategories = [.general]
                return
            }
            persist()
            LoggingService.setEnabledCategories(enabledLogCategories)
        }
    }

    @Published var showFingerprints: Bool {
        didSet {
            persist()
        }
    }

    private let defaults = UserDefaults.standard
    private let loggingLevelKey = "unifiedscanner:settings:loggingLevel"
    private let loggingCategoriesKey = "unifiedscanner:settings:loggingCategories"
    private let fingerprintsKey = "unifiedscanner:settings:showFingerprints"

    init() {
        if let raw = defaults.string(forKey: loggingLevelKey), let lvl = LoggingLevel(rawValue: raw) {
            loggingLevel = lvl
        } else {
            loggingLevel = .info
        }
        if let rawCategories = defaults.array(forKey: loggingCategoriesKey) as? [String] {
            let parsed = rawCategories.compactMap { LoggingService.Category(rawValue: $0) }
            enabledLogCategories = parsed.isEmpty ? Set(LoggingService.Category.allCases) : Set(parsed)
        } else {
            enabledLogCategories = Set(LoggingService.Category.allCases)
        }
        if defaults.object(forKey: fingerprintsKey) != nil {
            showFingerprints = defaults.bool(forKey: fingerprintsKey)
        } else {
            showFingerprints = true
        }
        LoggingService.setMinimumLevel(loggingLevel.scanLoggerLevel)
        LoggingService.setEnabledCategories(enabledLogCategories)
    }

    private func persist() {
        defaults.set(loggingLevel.rawValue, forKey: loggingLevelKey)
        defaults.set(Array(enabledLogCategories.map { $0.rawValue }), forKey: loggingCategoriesKey)
        defaults.set(showFingerprints, forKey: fingerprintsKey)
    }

    func binding(for category: LoggingService.Category) -> Binding<Bool> {
        Binding(
            get: { self.enabledLogCategories.contains(category) },
            set: { isOn in
                if isOn {
                    self.enabledLogCategories.insert(category)
                } else {
                    self.enabledLogCategories.remove(category)
                }
            }
        )
    }
}
