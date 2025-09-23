import Foundation

/// Provides mapping from Apple hardware identifiers (e.g. Mac14,2, iPhone14,7) to a concise
/// marketing family name (e.g. "MacBook Air", "iPhone 14"). Backed by the bundled
/// `appledevices.csv` file. Parsing is lazy & thread-safe similar to `OUILookupService`.
///
/// CSV columns: Device_Type,Generation,Identifier
/// - Device_Type: High-level family (e.g. "MacBook Air")
/// - Generation: Full marketing string (e.g. "MacBook Air (13-inch, M3, 2024)")
/// - Identifier: Hardware identifier (e.g. "Mac15,12")
///
/// For display we intentionally simplify:
/// - Prefer `Device_Type` for broad family grouping.
/// - For numbered iPhone/iPad generations we keep the number (e.g. iPhone 14, iPad Pro 11-inch) by
///   extracting from `Generation` when it provides meaningful discriminator beyond family.
/// - We drop chip / year suffixes to keep names concise.
final class AppleModelDatabase: @unchecked Sendable {
    static let shared = AppleModelDatabase()

    private var idToName: [String: String] = [:] // identifier(lowercased) -> simplified name
    private var loaded = false
    private let lock = NSLock()

    private init() {}

    /// Returns the raw Device_Type for the given model Identifier (exact match).
    /// e.g., "AppleTV14,1" -> "Apple TV" (as in CSV).
    func name(for modelIdentifier: String) -> String? {
        loadIfNeeded()
        if let exact = idToName[modelIdentifier] { return exact }
        // Case-insensitive fallback (avoid allocations by early check)
        let lowered = modelIdentifier.lowercased()
        if let ci = idToName.first(where: { $0.key.lowercased() == lowered })?.value { return ci }

        return nil
    }

    private func loadIfNeeded() {
        if loaded { return }
        lock.lock(); defer { lock.unlock() }
        if loaded { return }
        let candidateFiles = ["appledevices"]
        var raws: [String] = []
        for name in candidateFiles {
            if let url = resourceURL(named: name, extension: "csv") {
                do {
                    let s = try String(contentsOf: url, encoding: .utf8)
                    raws.append(s)
                } catch {
                    LoggingService.warn("AppleModelDatabase: failed to read \(name).csv — \(error.localizedDescription)", category: .vendor)
                }
            }
        }
        guard !raws.isEmpty else {
            LoggingService.warn("AppleModelDatabase: no apple model CSV resources found (looked for \(candidateFiles.joined(separator: ", ")))", category: .vendor)
            loaded = true
            return
        }
        let merged: String
        if raws.count == 1 {
            merged = raws[0]
        } else {
            // Merge all, keeping only first header line
            let headerAndFirst = raws[0]
            let restBody = raws.dropFirst().map { raw -> String in
                let norm = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                var lines = norm.split(separator: "\n", omittingEmptySubsequences: false)
                if !lines.isEmpty { lines.removeFirst() }
                return lines.joined(separator: "\n")
            }
            merged = ([headerAndFirst] + restBody).joined(separator: "\n")
        }
        parseAndBuild(raw: merged)
        loaded = true
        let loadedCount = self.idToName.count
        let fileCount = raws.count
        let logMessage = "AppleModelDatabase: loaded \(loadedCount) Apple model identifiers from \(fileCount) file(s)"
        LoggingService.info(logMessage, category: .vendor)
    }

    private func parseAndBuild(raw: String) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n")
        guard lines.count > 1 else { return }
        var map: [String: String] = [:]
        map.reserveCapacity(lines.count - 1)
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let cols = parseCSVLine(trimmed)
            guard cols.count >= 3 else {
                LoggingService.warn("AppleModelDatabase: skipped invalid row with \(cols.count) columns: \(trimmed)", category: .vendor)
                continue
            }
            let deviceType = cols[0].trimmingCharacters(in: .whitespaces)
            let identifier = cols[2].trimmingCharacters(in: .whitespaces)
            guard !identifier.isEmpty else { continue }
            map[identifier] = deviceType
        }
        idToName = map
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var value = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let char = line[i]
            let nextIndex = line.index(after: i)
            if char == "\"" {
                // Check for escaped quote: if next is \", don't toggle, append \"
                if nextIndex < line.endIndex && line[nextIndex] == "\"" {
                    value.append(char)
                    value.append(line[nextIndex])
                    i = line.index(after: nextIndex)
                    continue
                }
                inQuotes.toggle()
                i = nextIndex
                continue
            }
            if char == "," && !inQuotes {
                result.append(value)
                value = ""
                i = nextIndex
                continue
            }
            value.append(char)
            i = nextIndex
        }
        result.append(value)
        return result
    }

    private func resourceURL(named name: String, extension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        return Bundle.us_moduleIfAvailable?.url(forResource: name, withExtension: ext)
    }
}

private extension Bundle {
    static var us_moduleIfAvailable: Bundle? {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleToken_AppleModelDB.self)
        #endif
    }
}
private final class BundleToken_AppleModelDB {}
