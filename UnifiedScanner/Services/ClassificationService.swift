import Foundation

// MARK: - OUI Lookup Protocol

// OUI lookup protocol (lightweight hook; implementation can be injected later)
protocol OUILookupProviding: Sendable {
    func vendorFor(mac: String) -> String?
}

// MARK: - OUI Lookup Manager
private actor OUILookupManager {
    private var lookup: OUILookupProviding?

    func setLookup(_ lookup: OUILookupProviding?) {
        self.lookup = lookup
    }

    func getLookup() -> OUILookupProviding? {
        return lookup
    }
}

private let ouiLookupManager = OUILookupManager()

extension ClassificationService {
    static func setOUILookupProvider(_ provider: OUILookupProviding?) {
        Task { await ouiLookupManager.setLookup(provider) }
    }
}

// MARK: - Classification Service

// ClassificationService: expanded, modular rule groups with optional OUI (vendor prefix) hook.
struct ClassificationService {
    struct MatchResult {
        let formFactor: DeviceFormFactor?
        let rawType: String?
        let confidence: ClassificationConfidence
        let reason: String
        let sources: [String]
    }

    static func classify(device: Device) async -> Device.Classification {
        var candidates: [MatchResult] = []
        let lowerHost = device.hostname?.lowercased() ?? ""
        let explicitVendor = device.vendor?.lowercased() ?? ""
        let fingerprintResult = VendorModelExtractorService.extract(from: device.fingerprints ?? [:], hostname: device.hostname)
        let fingerprintVendor = fingerprintResult.vendor?.lowercased() ?? ""
        let fingerprintModelRaw = fingerprintResult.model ?? ""
        let fingerprintModel = fingerprintModelRaw.lowercased()
        let modelHint = device.modelHint?.lowercased() ?? ""
        let fingerprintValues = device.fingerprints?.values.map { $0.lowercased() } ?? []
        let fingerprintCorpusComponents = fingerprintValues + (modelHint.isEmpty ? [] : [modelHint])
        let fingerprintCorpus = fingerprintCorpusComponents.joined(separator: " ")
        let inferredVendor = (await inferVendorFromOUI(mac: device.macAddress))?.lowercased() ?? ""
        // Prefer explicit vendor, then fingerprint, then OUI
        let vendor = [explicitVendor, fingerprintVendor, inferredVendor].first(where: { !$0.isEmpty }) ?? ""
        let services = device.services
        let serviceTypes = Set(services.map { $0.type })
        let ports = Set(device.openPorts.map { $0.number })

        func add(_ form: DeviceFormFactor?, _ raw: String? = nil, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) {
            candidates.append(MatchResult(formFactor: form, rawType: raw, confidence: conf, reason: reason, sources: sources))
        }

        // MARK: - Fingerprint / Model Hint Rules FIRST (authoritative pass)
        fingerprintRules(vendor: vendor,
                         fingerprintModel: fingerprintModel,
                         fingerprintModelRaw: fingerprintModelRaw,
                         fingerprintCorpus: fingerprintCorpus,
                         fingerprintValues: fingerprintValues,
                         serviceTypes: serviceTypes,
                         fingerprints: device.fingerprints,
                         add: add)
        if let authoritative = candidates.first(where: { $0.confidence == .high && $0.sources.contains(where: { $0.hasPrefix("fingerprint") }) }) {
            LoggingService.debug("Authoritative fingerprint classification short-circuited: \(authoritative.reason)", category: .classification)
            return Device.Classification(formFactor: authoritative.formFactor, rawType: authoritative.rawType, confidence: authoritative.confidence, reason: authoritative.reason + " (authoritative)", sources: authoritative.sources)
        }

        // MARK: - High Confidence Hostname Patterns
        hostnamePatternRules(vendor: vendor, host: lowerHost, services: services, add: add)

        // MARK: - High Confidence Vendor / Hostname Patterns
        vendorHostnameRules(vendor: vendor, host: lowerHost, services: serviceTypes, ports: ports, add: add)

        // MARK: - Service Combination Rules (medium/high)
        serviceCombinationRules(vendor: vendor, host: lowerHost, services: serviceTypes, add: add)

        // MARK: - Port / Minimal Exposure Heuristics (IoT / Embedded)
        portProfileRules(vendor: vendor, services: serviceTypes, ports: ports, device: device, add: add)

        // MARK: - Fallback / Generic Low Confidence Rules
        fallbackRules(services: services, serviceTypes: serviceTypes, add: add)

        // Consolidate: pick highest confidence, then prefer more sources.
        if let best = candidates.sorted(by: { (a, b) -> Bool in
            if a.confidence == b.confidence {
                if a.formFactor == nil && b.formFactor != nil { return false }
                if a.formFactor != nil && b.formFactor == nil { return true }
                return a.sources.count > b.sources.count
            }
            return a.confidencePriority > b.confidencePriority
        }).first {
            return Device.Classification(formFactor: best.formFactor, rawType: best.rawType, confidence: best.confidence, reason: best.reason, sources: best.sources)
        }
        return Device.Classification(formFactor: nil, rawType: nil, confidence: .unknown, reason: "No rules matched", sources: [])
    }

    // MARK: - Rule Groups
    private static func hostnamePatternRules(vendor: String, host: String, services: [NetworkService], add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        guard !host.isEmpty else { return }
        guard !services.isEmpty else { return }
        struct Pattern {
            let token: String
            let formFactor: DeviceFormFactor?
            let rawType: String?
            let confidence: ClassificationConfidence
            let requiresAppleVendor: Bool
        }

        let patterns: [Pattern] = [
            Pattern(token: "iphone", formFactor: .phone, rawType: "iphone", confidence: .high, requiresAppleVendor: true),
            Pattern(token: "ipad", formFactor: .tablet, rawType: "ipad", confidence: .high, requiresAppleVendor: true),
            Pattern(token: "macbook", formFactor: .laptop, rawType: "mac", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "mac-mini", formFactor: .computer, rawType: "mac_mini", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "macmini", formFactor: .computer, rawType: "mac_mini", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "imac", formFactor: .computer, rawType: "imac", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "appletv", formFactor: .tv, rawType: "apple_tv", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "apple-tv", formFactor: .tv, rawType: "apple_tv", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "homepod", formFactor: .speaker, rawType: "homepod", confidence: .medium, requiresAppleVendor: true)
        ]

        let hasAppleVendor = vendor.contains("apple") || vendor.contains("ios") || vendor.contains("mac")
        let appleServiceTypes: Set<NetworkService.ServiceType> = [.airplay, .airplayAudio, .homekit]
        let appleRawTokens = ["_asquic.", "_companion-link.", "_device-info.", "_touch-able.", "_mediaremotetv.", "_sleep-proxy.", "_remotepairing.", "_apple-mobdev2."]
        let hasAppleService = services.contains { svc in
            if appleServiceTypes.contains(svc.type) { return true }
            guard let raw = svc.rawType?.lowercased() else { return false }
            return appleRawTokens.contains { raw.contains($0) }
        }

        for pattern in patterns where host.contains(pattern.token) {
            if pattern.requiresAppleVendor {
                if !hasAppleVendor && !hasAppleService { continue }
            }
            add(pattern.formFactor,
                pattern.rawType,
                pattern.confidence,
                "Hostname contains '" + pattern.token + "'",
                ["host:" + pattern.token])
            break
        }
    }

    private static func vendorHostnameRules(vendor: String, host: String, services: Set<NetworkService.ServiceType>, ports: Set<Int>, add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        // Printers
        if services.contains(.printer) || services.contains(.ipp) || host.contains("printer") {
            if containsAny(vendor, ["hp", "canon", "epson", "brother"]) {
                add(.printer, "network_printer", .high, "Printer service + known vendor", ["service:printer", "vendor:printer"]) }
            else { add(.printer, "network_printer", .medium, "Printer service or hostname", ["service:printer"]) }
        }
        // Routers / gateways
        if host.contains("router") || host.contains("gateway") || host.contains("fw") {
            if containsAny(vendor, ["ubiquiti", "netgear", "tplink", "tp-link", "asus", "synology", "mikrotik", "linksys"]) {
                add(.router, "router", .high, "Hostname router/gateway + network vendor", ["host:router", "vendor:network"]) }
            else { add(.router, "router", .medium, "Hostname router/gateway", ["host:router"]) }
        }
        // Apple TV hostname pattern (without fingerprint)
        if vendor.contains("apple") && (host.contains("apple-tv") || host.contains("appletv")) {
            add(.tv, nil, .high, "Hostname indicates Apple TV", ["host:appletv"])
        }
        // Raspberry Pi hostname patterns
        if host.contains("raspberrypi") || host == "pi" || host.hasPrefix("pi-") {
            add(.computer, "raspberry_pi", .medium, "Hostname indicates Raspberry Pi", ["host:raspberrypi"]) }
        // Chromecast
        if services.contains(.chromecast) {
            add(.tv, "chromecast", .medium, "Chromecast service", ["mdns:chromecast"]) }
        // Xiaomi / TP-Link smart plug style hostnames (iot)
        if containsAny(vendor, ["xiaomi", "tplink", "tp-link"]) && (host.contains("plug") || host.contains("smart")) {
            add(.iot, "smart_plug", .medium, "Smart plug hostname + vendor", ["host:plug", "vendor:smart"]) }
        // Xiaomi specific hostnames
        if host.hasPrefix("zhimi-airpurifier-") {
            add(.iot, "xiaomi_air_purifier", .high, "Hostname indicates Xiaomi Air Purifier", ["host:zhimi-airpurifier"])
        } else if host.hasPrefix("xiaomi-repeater-") {
            add(.router, "xiaomi_repeater", .high, "Hostname indicates Xiaomi Repeater", ["host:xiaomi-repeater"])
        }
    }

    private static func serviceCombinationRules(vendor: String, host: String, services: Set<NetworkService.ServiceType>, add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        // Apple computer heuristic (SSH + AirPlay) — medium confidence fallback when no fingerprint
        if vendor.contains("apple") && services.contains(.ssh) && services.contains(.airplay) {
            add(.computer, "mac", .medium, "SSH + AirPlay + Apple vendor", ["service:ssh", "service:airplay", "vendor:apple"])
        }
        // Ubiquiti management (ssh + http)
        if vendor.contains("ubiquiti") && services.contains(.ssh) && services.contains(.http) {
            add(.router, "ubiquiti_device", .medium, "SSH + HTTP mgmt + ubiquiti", ["service:ssh", "service:http", "vendor:ubiquiti"]) }
        // HomeKit accessory (homekit only)
        if services.contains(.homekit) && services.count == 1 {
            add(.accessory, "homekit_accessory", .medium, "Single HomeKit service", ["service:homekit"]) }
        // HomePod heuristic: RAOP / AirPlay Audio only (no generic AirPlay, no SSH) + Apple vendor
        if vendor.contains("apple") && services.contains(.airplayAudio) && !services.contains(.airplay) && !services.contains(.ssh) {
            add(.speaker, "homepod", .medium, "AirPlay Audio only + Apple vendor", ["service:airplayAudio", "vendor:apple"]) }
        else if (services.contains(.airplay) || services.contains(.airplayAudio)) && !services.contains(.ssh) && !services.contains(.printer) {
            // Generic AirPlay target (non-computer, non-HomePod RAOP-only case)
            let src = services.contains(.airplayAudio) && !services.contains(.airplay) ? ["service:airplayAudio"] : ["service:airplay"]
            add(.tv, "airplay_target", .medium, "AirPlay without SSH", src) }
    }

    private static func portProfileRules(vendor: String, services: Set<NetworkService.ServiceType>, ports: Set<Int>, device: Device, add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        // Single HTTP port + known consumer vendor => IoT
        if services.isEmpty && ports == [80] && containsAny(vendor, ["tp-link", "tplink", "xiaomi"]) {
            add(.iot, "embedded_http", .medium, "Only port 80 + consumer vendor", ["port:80", "vendor:consumer"]) }
        // Single HTTP port no vendor => low confidence IoT
        if services.isEmpty && device.openPorts.count == 1 && ports.contains(80) && vendor.isEmpty {
            add(.iot, "embedded_http", .low, "Single HTTP port only", ["port:80"]) }
        // NAS heuristic: SMB + (HTTP or HTTPS)
        if (services.contains(.smb) || ports.contains(445) || ports.contains(139)) && (services.contains(.http) || services.contains(.https) || ports.contains(80) || ports.contains(443)) {
            add(.server, "nas", .medium, "File sharing + web mgmt", ["service:smb_or_ports", "port:web"]) }
    }

    private static func fallbackRules(services: [NetworkService], serviceTypes: Set<NetworkService.ServiceType>, add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        // SSH-only host
        if serviceTypes == [.ssh] || (services.count == 1 && services.first?.type == .ssh) {
            add(.server, "ssh_only", .low, "Only SSH service discovered", ["service:ssh"]) }
    }

    private static func fingerprintRules(vendor: String,
                                         fingerprintModel: String,
                                         fingerprintModelRaw: String,
                                         fingerprintCorpus: String,
                                         fingerprintValues: [String],
                                         serviceTypes: Set<NetworkService.ServiceType>,
                                         fingerprints: [String: String]?,
                                         add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        let hasFingerprintData = !fingerprintModel.isEmpty || !fingerprintCorpus.isEmpty
        guard hasFingerprintData else { return }
        let modelSources = fingerprintModel.isEmpty ? [] : ["fingerprint:model"]
        let httpSources = fingerprintCorpus.isEmpty ? [] : ["fingerprint:http"]
        let appleContext = vendor.contains("apple") || fingerprintCorpus.contains("apple") || fingerprintModel.contains("apple") || fingerprintModel.hasPrefix("mac") || fingerprintModel.hasPrefix("appletv")

        // Apple-specific classification now broad only (family refinement happens in AppleDisplayNameResolver)
        if appleContext && classifyAppleModel(fingerprintModelRaw: fingerprintModelRaw,
                                              fingerprintModel: fingerprintModel,
                                              modelSources: modelSources,
                                              httpSources: httpSources,
                                              add: add) {
            return
        }

        if appleContext && (fingerprintModel.contains("appletv") || fingerprintCorpus.contains("appletv")) {
            add(.tv, nil, .high, "Fingerprint indicates Apple TV", !modelSources.isEmpty ? modelSources : httpSources)
        }
        if appleContext && (fingerprintModel.contains("homepod") || fingerprintModel.contains("audioaccessory") || fingerprintCorpus.contains("homepod") || fingerprintCorpus.contains("audioaccessory")) {
            add(.speaker, "homepod", .high, "Fingerprint indicates HomePod", !modelSources.isEmpty ? modelSources : httpSources)
        }
        if appleContext && (fingerprintModel.hasPrefix("macbook")) {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.laptop, nil, .high, "Fingerprint indicates MacBook", sources)
        }
        if appleContext && (fingerprintModel.hasPrefix("macmini") || fingerprintModel.contains("mac mini")) {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.computer, nil, .high, "Fingerprint indicates Mac mini class", sources)
        }
        if appleContext && fingerprintModel.hasPrefix("imac") { add(.computer, nil, .high, "Fingerprint indicates iMac", !modelSources.isEmpty ? modelSources : httpSources) }
        if appleContext && fingerprintModel.hasPrefix("macpro") { add(.computer, nil, .high, "Fingerprint indicates Mac Pro", !modelSources.isEmpty ? modelSources : httpSources) }
        if appleContext && fingerprintModel.hasPrefix("macstudio") { add(.computer, nil, .high, "Fingerprint indicates Mac Studio", !modelSources.isEmpty ? modelSources : httpSources) }
        if appleContext && (fingerprintModel.hasPrefix("iphone") || fingerprintModel.hasPrefix("ipod")) { add(.phone, nil, .high, "Fingerprint indicates iPhone/iPod", !modelSources.isEmpty ? modelSources : httpSources) }
        if appleContext && fingerprintModel.hasPrefix("ipad") { add(.tablet, nil, .high, "Fingerprint indicates iPad", !modelSources.isEmpty ? modelSources : httpSources) }
        if appleContext && (fingerprintModel.hasPrefix("watch") || fingerprintModel.contains("watch")) { add(.accessory, nil, .medium, "Fingerprint indicates Apple Watch", !modelSources.isEmpty ? modelSources : httpSources) }
        if appleContext && fingerprintModel.hasPrefix("mac") && !fingerprintModel.hasPrefix("macbook") && !fingerprintModel.hasPrefix("macmini") && !fingerprintModel.hasPrefix("macpro") && !fingerprintModel.hasPrefix("macstudio") {
            add(.computer, nil, .medium, "Generic Mac fingerprint", !modelSources.isEmpty ? modelSources : httpSources)
        }

        let httpText = fingerprintCorpus
        let httpValues = fingerprintValues
        if containsAny(httpText, ["routeros"]) || httpValues.contains(where: { $0.contains("routeros") }) {
            add(.router, "routeros", .high, "HTTP fingerprint indicates RouterOS", httpSources)
        } else if (fingerprints?["txt"]?.contains("Echo") ?? false) || (fingerprints?["txt"]?.contains("Amazon") ?? false) || (fingerprints?["txt"]?.contains("Alexa") ?? false) || (fingerprints?["http"]?.contains("Echo") ?? false) || (fingerprints?["http"]?.contains("Alexa") ?? false) {
            add(.iot, "alexa_echo", .high, "Fingerprints indicate Amazon Echo/Alexa device", [ "fingerprints:echo" ])
        } else if serviceTypes.contains(where: { $0.rawValue == "_miio._udp" }) || (fingerprints?["txt"]?.contains("miio") ?? false) || (fingerprints?["txt"]?.contains("0xE0") ?? false) {
            add(.iot, "xiaomi", .high, "Miio service or TXT indicates Xiaomi IoT", [ "service:miio", "fingerprints:xiaomi" ])
        } else if containsAny(httpText, ["tp-link", "tplink", "archer"]) || httpValues.contains(where: { $0.contains("tp-link") || $0.contains("tplink") || $0.contains("archer") }) {
            add(.router, "tplink_router", .high, "HTTP fingerprint indicates TP-Link router", httpSources)
        }
        if containsAny(httpText, ["asus"]) || httpValues.contains(where: { $0.contains("asus") }) {
            add(.router, "asus_router", .high, "HTTP fingerprint indicates ASUS router", httpSources)
        }
        if containsAny(httpText, ["d-link", "dlink"]) || httpValues.contains(where: { $0.contains("d-link") || $0.contains("dlink") }) {
            add(.router, "dlink_router", .high, "HTTP fingerprint indicates D-Link router", httpSources)
        }
        if containsAny(httpText, ["netgear"]) || httpValues.contains(where: { $0.contains("netgear") }) {
            add(.router, "netgear_router", .high, "HTTP fingerprint indicates Netgear router", httpSources)
        }
        if containsAny(httpText, ["miwifi"]) || httpValues.contains(where: { $0.contains("miwifi") }) {
            add(.router, "xiaomi_router", .high, "HTTP fingerprint indicates Xiaomi MIWIFI router", httpSources)
        }
        if containsAny(httpText, ["synology"]) || httpValues.contains(where: { $0.contains("synology") }) {
            add(.server, "synology_nas", .high, "HTTP fingerprint indicates Synology", httpSources)
        }
        if containsAny(httpText, ["airport", "time capsule"]) {
            add(.router, "airport", .medium, "HTTP fingerprint indicates AirPort base station", httpSources)
        }
}

// MARK: - Helpers
private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool { needles.contains { haystack.contains($0) } }

private static func classifyAppleModel(fingerprintModelRaw: String,
                                       fingerprintModel: String,
                                       modelSources: [String],
                                       httpSources: [String],
                                       add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) -> Bool {
    guard !fingerprintModelRaw.isEmpty else { return false }
    let db = AppleModelDatabase.shared
    let trimmed = fingerprintModelRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let candidates = [trimmed, trimmed.lowercased(), trimmed.uppercased(), fingerprintModel]
    guard let mappedName = candidates.compactMap({ db.name(for: $0) }).first else { return false }
    guard let formFactor = appleFormFactor(for: mappedName) else { return false }
    let normalizedRawType = mappedName.lowercased().replacingOccurrences(of: " ", with: "_")
    var sources = !modelSources.isEmpty ? modelSources : httpSources
    if !sources.contains(where: { $0 == "apple:database" }) { sources.append("apple:database") }
    add(formFactor,
        normalizedRawType,
        .high,
        "Fingerprint model maps to Apple database (\(mappedName))",
        sources)
    return true
}

private static func appleFormFactor(for name: String) -> DeviceFormFactor? {
    let lower = name.lowercased()
    if lower.contains("iphone") || lower.contains("ipod") { return .phone }
    if lower.contains("ipad") { return .tablet }
    if lower.contains("macbook") { return .laptop }
    if lower.contains("imac") || lower.contains("mac mini") || lower.contains("macmini") || lower.contains("mac studio") || lower.contains("mac pro") { return .computer }
    if lower.contains("mac") { return .computer }
    if lower.contains("apple tv") || lower.contains("appletv") { return .tv }
    if lower.contains("homepod") { return .speaker }
    if lower.contains("watch") { return .accessory }
    if lower.contains("airpods") { return .accessory }
    return nil
}

    private static func inferVendorFromOUI(mac: String?) async -> String? {
        guard let mac = mac?.replacingOccurrences(of: "-", with: ":").uppercased(), mac.count >= 8 else { return nil }
        let lookup = await ouiLookupManager.getLookup()
        return lookup?.vendorFor(mac: mac)
    }
}

private extension ClassificationService.MatchResult {
    var confidencePriority: Int {
        switch confidence { case .high: return 3; case .medium: return 2; case .low: return 1; case .unknown: return 0 }
    }
}
