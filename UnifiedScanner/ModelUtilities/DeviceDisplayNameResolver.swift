import Foundation

struct ResolvedName { let value: String; let score: Int; let sources: [String] }

enum DeviceDisplayNameResolver {
    static func resolve(for device: Device) -> ResolvedName? {
        if let user = device.name?.trimmedNonEmpty { return ResolvedName(value: user, score: 100, sources: ["user"]) }
        var candidates: [ResolvedName] = []
        func add(_ value: String?, _ score: Int, _ source: String) {
            guard let v = value?.trimmedNonEmpty else { return }
            candidates.append(ResolvedName(value: v, score: score, sources: [source]))
        }
        let normalizedHost = HostnameNormalizer.normalize(device.hostname)
        add(highConfidenceModel(device) ?? inferredAppleModelFromHostname(normalizedHost.original), 90, "model")
        add(classificationName(device), classificationScore(device.classification), "classification")
        if normalizedHost.isMeaningful { add(normalizedHost.cleaned, 60, "hostname") }
        add(vendorOnly(device), 40, "vendor")
        add(device.bestDisplayIP, 20, "ip")
        add(device.id, 0, "id")
        // Remove pure numeric/mostly numeric hostname OR id candidates if higher scored, human names exist
        let hasNonNumeric = candidates.contains { !$0.value.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" || $0 == " " || $0 == "," }) && $0.score >= 40 }
        if hasNonNumeric {
            candidates.removeAll { $0.score <= 20 && $0.value.allSatisfy { $0.isNumber || [".", ":", " ", ","].contains($0) } }
            // Also remove pathological comma-separated numeric like "0,1,2" if better exists
            candidates.removeAll { $0.score <= 60 && $0.value.replacingOccurrences(of: ",", with: "").allSatisfy { $0.isNumber } }
        }
        if var best = candidates.max(by: { $0.score < $1.score }) {
            best = postProcess(best)
            return best
        }
        return nil
    }

    private static func highConfidenceModel(_ d: Device) -> String? {
        guard let raw = d.modelHint?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        // Ignore model hints that are purely numeric/commas/periods (likely CN fingerprint noise)
        let noiseSet = CharacterSet(charactersIn: "0123456789.,: ")
        if raw.unicodeScalars.allSatisfy({ noiseSet.contains($0) }) { return nil }
        // Try exact hardware identifier lookup first (case-insensitive). Allow canonicalizer to refine for certain families.
        if let mapped = AppleModelDatabase.shared.name(for: raw) {
            let lowerRaw = raw.lowercased()
            if lowerRaw.hasPrefix("audioaccessory") {
                // Let canonicalizer distinguish HomePod mini vs HomePod generations
                return AppleModelCanonicalizer.canonical(lowerRaw) ?? mapped
            }
            return mapped
        }
        let lower = raw.lowercased()
        // Try stripping common punctuation variants (some sources may omit comma)
        if lower.contains(",") == false {
            // Insert a comma before last numeric segment if it looks like Mac1412 -> Mac14,12
            if let reconstructed = reconstructCommaIdentifier(lower), let mapped2 = AppleModelDatabase.shared.name(for: reconstructed) {
                if lower.hasPrefix("audioaccessory") {
                    return AppleModelCanonicalizer.canonical(lower) ?? mapped2
                }
                return mapped2
            }
        }
        return AppleModelCanonicalizer.canonical(lower) ?? XiaomiCanonicalizer.canonical(lower) ?? lower.titleCasedWords()
    }

    private static func classificationName(_ d: Device) -> String? {
        guard let c = d.classification else { return nil }
        if let raw = c.rawType?.replacingOccurrences(of: "_", with: " ") { return raw.titleCasedWords() }
        if let form = c.formFactor { return form.rawValue.replacingOccurrences(of: "_", with: " ").titleCasedWords() }
        return nil
    }

    private static func classificationScore(_ c: Device.Classification?) -> Int {
        guard let c else { return 0 }
        switch c.confidence { case .high: return 80; case .medium: return 70; case .low: return 50; case .unknown: return 0 }
    }

    private static func vendorOnly(_ d: Device) -> String? {
        guard let v = d.vendor?.trimmedNonEmpty else { return nil }
        return v.titleCasedIfLower()
    }
    private static func postProcess(_ resolved: ResolvedName) -> ResolvedName {
        let corrected = BrandCasing.correct(resolved.value)
        if corrected == resolved.value { return resolved }
        return ResolvedName(value: corrected, score: resolved.score, sources: resolved.sources + ["brand-casing"])
    }
    private static func inferredAppleModelFromHostname(_ host: String) -> String? {
        let h = host.lowercased()
        guard !h.isEmpty else { return nil }
        if h.contains("macbookair") || h.contains("macbook-air") { return "MacBook Air" }
        if h.contains("macbookpro") || h.contains("macbook-pro") { return "MacBook Pro" }
        if h.contains("macmini") || h.contains("mac-mini") { return "Mac Mini" }
        if h.contains("imac") { return "iMac" }
        if h.contains("macstudio") { return "Mac Studio" }
        if h.contains("macpro") { return "Mac Pro" }
        if h.contains("iphone") { return "iPhone" }
        if h.contains("ipad") { return "iPad" }
        if h.contains("appletv") || h.contains("apple-tv") { return "Apple TV" }
        if h.contains("homepod") || h.contains("home-pod") { return "HomePod" }
        return nil
    }
}

private enum HostnameNormalizer {
    struct NormalizedHost { let cleaned: String; let original: String; let isMeaningful: Bool }
    static func normalize(_ host: String?) -> NormalizedHost {
        guard var h = host?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty else {
            return NormalizedHost(cleaned: "", original: host ?? "", isMeaningful: false)
        }
        if h.hasSuffix(".") { h.removeLast() }
        if h.hasSuffix(".local") { h = String(h.dropLast(6)) }
        let base = h.replacingOccurrences(of: "_", with: "-")
        let parts = base.split(separator: "-")
        let cleaned = parts.joined(separator: " ")
        let lowered = cleaned.lowercased()
        let genericPatterns = ["device", "android", "unknown", "localhost"]
        // Suppress hostnames that are entirely numeric tokens (e.g. "0-1-2" -> "0 1 2") or mostly numeric noise
        let tokens = cleaned.split(separator: " ")
        let numericTokenCount = tokens.filter { $0.allSatisfy { $0.isNumber } }.count
        let allNumeric = !tokens.isEmpty && numericTokenCount == tokens.count
        let mostlyNumeric = tokens.count > 2 && numericTokenCount >= tokens.count - 1
        let isMeaningful = !allNumeric && !mostlyNumeric && !genericPatterns.contains { lowered == $0 } && lowered.count > 2
        return NormalizedHost(cleaned: cleaned.titleCasedWords(), original: h, isMeaningful: isMeaningful)
    }
}

private enum AppleModelCanonicalizer {
    static func canonical(_ raw: String) -> String? {
        let r = raw.lowercased()
        let collapsed = r.replacingOccurrences(of: "[\\s_-]", with: "", options: .regularExpression)
        // Direct / marketing string patterns (allow spaces, underscores, hyphens via collapsed)
        if collapsed.contains("macbookair") { return "MacBook Air" }
        if collapsed.contains("macbookpro") { return "MacBook Pro" }
        if collapsed.contains("macmini") { return "Mac mini" }
        if collapsed.hasPrefix("imac") { return "iMac" }
        if collapsed.contains("macstudio") { return "Mac Studio" }
        if collapsed.contains("macpro") { return "Mac Pro" }
        if collapsed.contains("iphone") { return "iPhone" }
        if collapsed.contains("ipad") { return "iPad" }
        if collapsed.contains("appletv") { return "Apple TV" }
        if collapsed.contains("homepod") { return "HomePod" }
        // Hardware identifier heuristics (single source of truth for HomePod mini detection)
        if r.hasPrefix("audioaccessory") {
            let suffix = r.dropFirst("audioaccessory".count)
            if let comma = suffix.firstIndex(of: ",") {
                let major = suffix[..<comma]
                if let majorNum = Int(major) {
                    if majorNum == 5 { return "HomePod mini" }
                    return "HomePod"
                }
            }
            return "HomePod" // fallback
        }
        if r.range(of: #"^appletv\d+,\d+$"#, options: .regularExpression) != nil { return "Apple TV" }
        if r.range(of: #"^mac\d+,\d+$"#, options: .regularExpression) != nil {
            let genericMap: [String: String] = [
                "mac16,10": "Mac mini",
                "mac16,11": "Mac mini",
                "mac16,12": "MacBook Air",
                "mac16,13": "MacBook Air",
                "mac16,1": "MacBook Pro",
                "mac16,6": "MacBook Pro",
                "mac16,8": "MacBook Pro",
                "mac16,5": "MacBook Pro",
                "mac16,7": "MacBook Pro",
                "mac16,2": "iMac",
                "mac16,3": "iMac",
                "mac16,9": "Mac Studio",
                "mac15,12": "MacBook Air",
                "mac15,13": "MacBook Air",
                "mac15,10": "MacBook Pro",
                "mac15,3": "MacBook Pro",
                "mac15,6": "MacBook Pro",
                "mac15,8": "MacBook Pro",
                "mac14,12": "Mac mini",
                "mac14,3": "Mac mini",
                "mac14,5": "MacBook Air",
                "mac14,10": "MacBook Pro",
                "mac14,13": "Mac Studio",
                "mac14,14": "Mac Studio"
            ]
            if let fam = genericMap[r] { return fam }
        }
        return nil
    }
}

private enum BrandCasing {
    static func correct(_ name: String) -> String {
        let map: [String: String] = [
            "homepod": "HomePod",
            "homepod mini": "HomePod mini",
            "apple tv": "Apple TV",
            "appletv": "Apple TV",
            "mac mini": "Mac mini",
            "macmini": "Mac mini",
            "macbook air": "MacBook Air",
            "macbook pro": "MacBook Pro",
            "imac": "iMac",
            "mac studio": "Mac Studio",
            "mac pro": "Mac Pro"
        ]
        let lowered = name.lowercased()
        if let exact = map[lowered] { return exact }
        var corrected = name
        // Normalize partial / mixed casing variants
        corrected = corrected.replacingOccurrences(of: "Homepod", with: "HomePod")
        corrected = corrected.replacingOccurrences(of: "Homepod Mini", with: "HomePod mini")
        corrected = corrected.replacingOccurrences(of: "HomePod Mini", with: "HomePod mini")
        // Apple TV variants
        corrected = corrected.replacingOccurrences(of: "Apple Tv", with: "Apple TV")
        corrected = corrected.replacingOccurrences(of: "Appletv", with: "Apple TV")
        corrected = corrected.replacingOccurrences(of: "appletv", with: "Apple TV", options: .caseInsensitive)
        // Collapse marketing strings like "Apple TV 4K (3rd generation)" -> "Apple TV"
        let loweredCorr = corrected.lowercased()
        if loweredCorr.hasPrefix("apple tv ") { return "Apple TV" }
        return corrected
    }
}

// Attempts to reconstruct a missing comma in identifiers like mac1412 -> mac14,12 or appletv141 -> appletv14,1
private func reconstructCommaIdentifier(_ raw: String) -> String? {
    // Match patterns: mac\d{3,}, appletv\d{3,}, iphone\d{3,}, ipad\d{3,}
    // Heuristic: split last two digits as minor if plausible (e.g. 1412 -> 14,12) when first 2 digits form known major bucket
    let patterns = ["mac", "appletv", "iphone", "ipad", "audioaccessory"]
    for prefix in patterns {
        if raw.hasPrefix(prefix) {
            let tail = raw.dropFirst(prefix.count)
            guard tail.count >= 3, tail.allSatisfy({ $0.isNumber }) else { return nil }
            // Try splitting: major can be 1-2 digits (sometimes 14, 15, 16 etc.) or up to 3 for iPhone17 etc.
            for majorLen in [2, 3] {
                if tail.count > majorLen {
                    let major = tail.prefix(majorLen)
                    let minor = tail.dropFirst(majorLen)
                    if major.first != "0" && minor.first != "0" { return prefix + major + "," + minor }
                }
            }
            // Fallback: first two digits / remaining
            let major = tail.prefix(2)
            let minor = tail.dropFirst(2)
            if major.first != "0" && minor.first != "0" { return prefix + major + "," + minor }
            return nil
        }
    }
    return nil
}

private enum XiaomiCanonicalizer {
    static func canonical(_ raw: String) -> String? {
        let r = raw.lowercased()
        if r.contains("airpurifier") { return "Xiaomi Air Purifier" }
        if r.contains("repeater") { return "Xiaomi Repeater" }
        if r.contains("router") || r.contains("miwifi") { return "Xiaomi Router" }
        return nil
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension String {
    func titleCasedWords() -> String {
        self.split(separator: " ").map { part in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }
    func titleCasedIfLower() -> String {
        let lower = self.lowercased()
        if self == lower { return self.titleCasedWords() }
        return self
    }
}
