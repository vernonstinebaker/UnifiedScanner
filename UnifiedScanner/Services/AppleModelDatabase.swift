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

    func name(for modelIdentifier: String) -> String? {
        loadIfNeeded()
        return idToName[modelIdentifier.lowercased()]
    }

    private func loadIfNeeded() {
        if loaded { return }
        lock.lock(); defer { lock.unlock() }
        if loaded { return }
        let candidateFiles = ["appledevices", "apple_models_simplified"]
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
            guard cols.count >= 3 else { continue }
            let deviceType = cols[0].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            let generation = cols[1].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            let identifier = cols[2].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            guard !identifier.isEmpty else { continue }
            let simplified = simplify(deviceType: deviceType, generation: generation)
            map[identifier.lowercased()] = simplified
        }
        idToName = map
    }

    private func simplify(deviceType: String, generation: String) -> String {
        let base = deviceType
        let lowerGen = generation.lowercased()
        if base == "iPhone" {
            if let match = firstMatch(pattern: #"iPhone[^\"]*"#, in: generation) {
                // Trim chip/year parentheticals if present
                return match.replacingOccurrences(of: #"\s*\([^\)]*\)"#, with: "", options: .regularExpression)
            }
            return base
        }
        if base.hasPrefix("iPad") {
            if let size = firstMatch(pattern: #"(1[0-9](?:\.\d)?|\d{1,2})\.?(?:\d)?-?inch"#, in: lowerGen) {
                return base + " " + size.replacingOccurrences(of: " ", with: "")
            }
            return base
        }
        if base == "HomePod" {
            // Defer HomePod mini disambiguation to AppleModelCanonicalizer (single source of truth)
            return base
        }
        if base == "Apple TV" { return base }
        if base == "Mac mini" || base == "Mac Studio" || base == "Mac Pro" || base == "iMac" || base == "MacBook Air" || base == "MacBook Pro" { return base }
        return base
    }

    private func firstMatch(pattern: String, in value: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: value.utf16.count)
            if let m = regex.firstMatch(in: value, options: [], range: range) {
                if let r = Range(m.range, in: value) { return String(value[r]) }
            }
        } catch { return nil }
        return nil
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var value = ""
        var inQuotes = false
        for char in line {
            if char == "\"" { inQuotes.toggle(); continue }
            if char == "," && !inQuotes { result.append(value); value = ""; continue }
            value.append(char)
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
