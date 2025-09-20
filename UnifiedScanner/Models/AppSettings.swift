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

    private let defaults = UserDefaults.standard
    private let loggingLevelKey = "unifiedscanner:settings:loggingLevel"

    init() {
        if let raw = defaults.string(forKey: loggingLevelKey), let lvl = LoggingLevel(rawValue: raw) {
            loggingLevel = lvl
        } else {
            loggingLevel = .info
        }
        LoggingService.setMinimumLevel(loggingLevel.scanLoggerLevel)
    }

    private func persist() {
        defaults.set(loggingLevel.rawValue, forKey: loggingLevelKey)
    }


}

// SettingsView extracted to Views/SettingsView.swift
