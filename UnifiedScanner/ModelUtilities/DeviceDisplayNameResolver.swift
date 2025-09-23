import Foundation

// MARK: - Public Resolved Name Struct
struct ResolvedName { let value: String; let score: Int; let sources: [String] }

// MARK: - Orchestrator
// High-level display name resolver delegating vendor-specific logic to pluggable resolvers.
enum DeviceDisplayNameResolver {
    static func resolve(for device: Device) -> ResolvedName? {
        if let user = device.name?.trimmedNonEmpty { return ResolvedName(value: user, score: 100, sources: ["user"]) }
        let ctx = ResolveContext()
        var candidates: [ResolvedName] = []
        func add(_ v: String?, _ score: Int, _ source: String) { guard let val = v?.trimmedNonEmpty else { return }; candidates.append(ResolvedName(value: val, score: score, sources: [source])) }

        // 1. Vendor-specific resolver (if any)
        let vendorResolver = VendorResolverFactory.resolver(for: device.vendor)
        if let vendorCandidate = vendorResolver.resolve(device: device, context: ctx) { candidates.append(vendorCandidate) }

        // 2. Generic fallbacks
        let normalizedHost = HostnameNormalizer.normalize(device.hostname)
        if normalizedHost.isMeaningful { add(normalizedHost.cleaned, 60, "hostname") }
        add(genericClassificationName(device), classificationScore(device.classification), "classification")
        add(vendorOnly(device), 40, "vendor")
        add(device.bestDisplayIP, 20, "ip")
        add(device.id, 0, "id")

        // 3. Numeric noise suppression
        let hasNonNumeric = candidates.contains { !$0.value.isNumericLike && $0.score >= 40 }
        if hasNonNumeric {
            candidates.removeAll { $0.score <= 20 && $0.value.isNumericLike }
            candidates.removeAll { $0.score <= 60 && $0.value.replacingOccurrences(of: ",", with: "").allSatisfy { $0.isNumber } }
        }

        guard var best = candidates.max(by: { $0.score < $1.score }) else { return nil }
        best = BrandPostProcessor.process(best)
        return best
    }
}

// MARK: - Vendor Resolver Protocol & Factory
protocol VendorDisplayNameResolving { func resolve(device: Device, context: ResolveContext) -> ResolvedName? }
struct ResolveContext { let modelDB = AppleModelDatabase.shared }

enum VendorResolverFactory {
    static func resolver(for vendor: String?) -> VendorDisplayNameResolving {
        guard let v = vendor?.lowercased() else { return GenericVendorResolver() }
        if v.contains("apple") { return AppleDisplayNameResolver() }
        if v.contains("xiaomi") { return XiaomiDisplayNameResolver() }
        return GenericVendorResolver()
    }
}

// MARK: - Apple Resolver
struct AppleDisplayNameResolver: VendorDisplayNameResolving {
    func resolve(device: Device, context: ResolveContext) -> ResolvedName? {
        // Prefer fingerprint-extracted hardware identifier over legacy modelHint
        if let fpModel = VendorModelExtractorService.extract(from: device.fingerprints ?? [:], hostname: device.hostname).model?.trimmingCharacters(in: .whitespacesAndNewlines), !fpModel.isEmpty {
            if let resolved = resolveModel(raw: fpModel, db: context.modelDB) {
                return ResolvedName(value: resolved, score: 90, sources: ["fingerprint:model"])
            }
        }
        // Fallback: legacy stored modelHint (temporary backward compatibility)
        if let raw = device.modelHint?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if let resolved = resolveModel(raw: raw, db: context.modelDB) {
                return ResolvedName(value: resolved, score: 85, sources: ["modelHint"])
            }
        }
        // Hostname inference if no model
        if let host = device.hostname, let inferred = inferFromHostname(host) { return ResolvedName(value: inferred, score: 70, sources: ["hostname-model"]) }
        // Classification (broad) already handled generically; nothing Apple-specific remaining
        // However if we have only a tv form factor and no better candidate, still provide Apple TV explicitly.
        if device.classification?.formFactor == .tv { return ResolvedName(value: "Apple TV", score: 65, sources: ["apple-formfactor"]) }
        return nil
    }

    private func resolveModel(raw: String, db: AppleModelDatabase) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isPurelyNumericPunctuation else { return nil }
        // Only attempt direct (case-insensitive) database lookup; no heuristic reconstruction.
        if let mapped = db.name(for: trimmed) { return mapped }
        return nil
    }

    private func refine(raw: String, mapped: String) -> String { mapped }

    private func inferFromHostname(_ host: String) -> String? {
        let h = host.lowercased()
        if h.contains("macbookair") || h.contains("macbook-air") { return "MacBook Air" }
        if h.contains("macbookpro") || h.contains("macbook-pro") { return "MacBook Pro" }
        if h.contains("macmini") || h.contains("mac-mini") { return "Mac mini" }
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

// MARK: - Xiaomi Resolver
struct XiaomiDisplayNameResolver: VendorDisplayNameResolving {
    func resolve(device: Device, context: ResolveContext) -> ResolvedName? {
        guard let raw = device.modelHint?.lowercased() ?? device.hostname?.lowercased() else { return nil }
        if raw.contains("airpurifier") { return ResolvedName(value: "Xiaomi Air Purifier", score: 70, sources: ["model"]) }
        if raw.contains("repeater") { return ResolvedName(value: "Xiaomi Repeater", score: 70, sources: ["model"]) }
        if raw.contains("router") || raw.contains("miwifi") { return ResolvedName(value: "Xiaomi Router", score: 70, sources: ["model"]) }
        return nil
    }
}

// MARK: - Generic Vendor Resolver
struct GenericVendorResolver: VendorDisplayNameResolving { func resolve(device: Device, context: ResolveContext) -> ResolvedName? { nil } }

// MARK: - Brand Post Processor
private enum BrandPostProcessor {
    static func process(_ resolved: ResolvedName) -> ResolvedName {
        let corrected = BrandCasing.correct(resolved.value)
        if corrected == resolved.value { return resolved }
        return ResolvedName(value: corrected, score: resolved.score, sources: resolved.sources + ["brand-casing"]) }
}

// MARK: - Hostname Normalizer (unchanged logic, reused)
private enum HostnameNormalizer {
    struct NormalizedHost { let cleaned: String; let original: String; let isMeaningful: Bool }
    static func normalize(_ host: String?) -> NormalizedHost {
        guard var h = host?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty else { return NormalizedHost(cleaned: "", original: host ?? "", isMeaningful: false) }
        if h.hasSuffix(".") { h.removeLast() }
        if h.hasSuffix(".local") { h = String(h.dropLast(6)) }
        let base = h.replacingOccurrences(of: "_", with: "-")
        let parts = base.split(separator: "-")
        let cleaned = parts.joined(separator: " ")
        let lowered = cleaned.lowercased()
        let genericPatterns = ["device", "android", "unknown", "localhost"]
        let tokens = cleaned.split(separator: " ")
        let numericCount = tokens.filter { $0.allSatisfy { $0.isNumber } }.count
        let allNumeric = !tokens.isEmpty && numericCount == tokens.count
        let mostlyNumeric = tokens.count > 2 && numericCount >= tokens.count - 1
        let isMeaningful = !allNumeric && !mostlyNumeric && !genericPatterns.contains { lowered == $0 } && lowered.count > 2
        return NormalizedHost(cleaned: cleaned.titleCasedWords(), original: h, isMeaningful: isMeaningful)
    }
}

// MARK: - Brand Casing
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
        corrected = corrected.replacingOccurrences(of: "Homepod", with: "HomePod")
        corrected = corrected.replacingOccurrences(of: "Homepod Mini", with: "HomePod mini")
        corrected = corrected.replacingOccurrences(of: "HomePod Mini", with: "HomePod mini")
        corrected = corrected.replacingOccurrences(of: "Apple Tv", with: "Apple TV")
        corrected = corrected.replacingOccurrences(of: "Appletv", with: "Apple TV")
        corrected = corrected.replacingOccurrences(of: "appletv", with: "Apple TV", options: .caseInsensitive)
        if corrected.lowercased().hasPrefix("apple tv ") { return "Apple TV" }
        return corrected
    }
}


// MARK: - Generic helpers
private func genericClassificationName(_ d: Device) -> String? { // broad form factor only; remove Apple-specific family mapping
    guard let c = d.classification else { return nil }
    if let raw = c.rawType?.replacingOccurrences(of: "_", with: " ") { return raw.titleCasedWords() }
    if let form = c.formFactor { return form.rawValue.replacingOccurrences(of: "_", with: " ").titleCasedWords() }
    return nil
}

private func classificationScore(_ c: Device.Classification?) -> Int { guard let c else { return 0 }; switch c.confidence { case .high: return 80; case .medium: return 70; case .low: return 50; case .unknown: return 0 } }
private func vendorOnly(_ d: Device) -> String? { d.vendor?.trimmedNonEmpty?.titleCasedIfLower() }


// MARK: - Extensions
private extension String { var trimmedNonEmpty: String? { let t = trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t } }
private extension String { func titleCasedWords() -> String { split(separator: " ").map { part in guard let f = part.first else { return "" }; return String(f).uppercased() + part.dropFirst() }.joined(separator: " ") } }
private extension String { func titleCasedIfLower() -> String { let lower = self.lowercased(); return self == lower ? self.titleCasedWords() : self } }
private extension String {
    var isNumericLike: Bool { allSatisfy { $0.isNumber || [".",":"," ",","].contains($0) } }
    var isPurelyNumericPunctuation: Bool { isNumericLike }
}
