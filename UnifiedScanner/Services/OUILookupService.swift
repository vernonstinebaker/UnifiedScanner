import Foundation

/// Lightweight, synchronous OUI lookup used by `ClassificationService`.
/// Parses `oui.csv` lazily and caches the vendor prefix mapping in-memory.
final class OUILookupService: OUILookupProviding, @unchecked Sendable {
    static let shared = OUILookupService()

    private var vendorCache: [String: String] = [:]
    private var loaded = false
    private let loadLock = NSLock()

    private init() {}

    func vendorFor(mac: String) -> String? {
        loadIfNeeded()
        let normalized = mac
            .uppercased()
            .replacingOccurrences(of: "-", with: ":")
        let prefix = normalized.split(separator: ":").prefix(3).joined()
        guard !prefix.isEmpty else { return nil }
        return vendorCache[prefix]
    }

    private func loadIfNeeded() {
        if loaded { return }
        loadLock.lock()
        defer { loadLock.unlock() }
        if loaded { return }

        guard let url = resourceURL(named: "oui", extension: "csv") else {
            LoggingService.warn("OUILookupService: oui.csv not found in bundle resources", category: .vendor)
            loaded = true
            return
        }

        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let lines = normalized.split(separator: "\n")
            guard !lines.isEmpty else {
                LoggingService.warn("OUILookupService: oui.csv is empty", category: .vendor)
                loaded = true
                return
            }
            let dataLines = lines.dropFirst()
            var cache: [String: String] = [:]
            cache.reserveCapacity(dataLines.count)
            for line in dataLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let columns = parseCSVLine(trimmed)
                guard columns.count >= 3 else { continue }
                let registry = columns[0]
                guard registry == "MA-L" else { continue }
                let assignment = columns[1].replacingOccurrences(of: "\"", with: "").uppercased()
                let vendor = columns[2].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard assignment.count == 6, !vendor.isEmpty else { continue }
                cache[assignment] = vendor
            }
            vendorCache = cache
            loaded = true
            LoggingService.info("OUILookupService: loaded \(self.vendorCache.count) OUI entries", category: .vendor)
        } catch {
            LoggingService.warn("OUILookupService: failed to load oui.csv — \(error.localizedDescription)", category: .vendor)
            loaded = true
        }
    }

    private func resourceURL(named name: String, extension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.moduleIfAvailable?.url(forResource: name, withExtension: ext)
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var value = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
                continue
            }
            if char == "," && !inQuotes {
                result.append(value)
                value = ""
                continue
            }
            value.append(char)
        }
        result.append(value)
        return result
    }
}

private extension Bundle {
    /// Access the bundle that defines `OUILookupService` when available (useful for unit tests).
    static var moduleIfAvailable: Bundle? {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleToken.self)
        #endif
    }
}

private final class BundleToken {}
