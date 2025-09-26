import Foundation

struct ClassificationRuleContext: Sendable {
    let device: Device
    let vendor: String
    let host: String
    let services: [NetworkService]
    let serviceTypes: Set<NetworkService.ServiceType>
    let ports: Set<Int>
    let fingerprintModel: String
    let fingerprintModelRaw: String
    let fingerprintCorpus: String
    let fingerprintValues: [String]
    let fingerprints: [String: String]?
}

struct ClassificationAccumulator: Sendable {
    private(set) var matches: [ClassificationService.MatchResult] = []
    private(set) var shortCircuit: ShortCircuitMatch? = nil

    mutating func add(formFactor: DeviceFormFactor?,
                      rawType: String?,
                      confidence: ClassificationConfidence,
                      reason: String,
                      sources: [String],
                      shortCircuitAnnotation: String? = nil) {
        let result = ClassificationService.MatchResult(formFactor: formFactor,
                                                       rawType: rawType,
                                                       confidence: confidence,
                                                       reason: reason,
                                                       sources: sources)
        matches.append(result)
        if let annotation = shortCircuitAnnotation {
            markShortCircuit(result: result, annotation: annotation)
        }
    }

    struct ShortCircuitMatch: Sendable {
        let result: ClassificationService.MatchResult
        let annotation: String
    }

    mutating func markShortCircuit(result: ClassificationService.MatchResult, annotation: String) {
        guard shortCircuit == nil else { return }
        shortCircuit = ShortCircuitMatch(result: result, annotation: annotation)
    }
}

protocol ClassificationRule: Sendable {
    func evaluate(context: ClassificationRuleContext, accumulator: inout ClassificationAccumulator) async
}

struct ClassificationRulePipeline: Sendable {
    let rules: [any ClassificationRule]

    static var `default`: ClassificationRulePipeline {
        ClassificationRulePipeline(rules: [
            FingerprintClassificationRule(),
            HostnamePatternClassificationRule(),
            VendorHostnameClassificationRule(),
            ServiceCombinationClassificationRule(),
            PortProfileClassificationRule(),
            FallbackClassificationRule()
        ] as [any ClassificationRule])
    }
}

// MARK: - Individual Rules

struct FingerprintClassificationRule: ClassificationRule {
    func evaluate(context: ClassificationRuleContext, accumulator: inout ClassificationAccumulator) async {
        let hasFingerprintData = !context.fingerprintModel.isEmpty || !context.fingerprintCorpus.isEmpty
        guard hasFingerprintData else { return }
        let modelSources = context.fingerprintModel.isEmpty ? [] : ["fingerprint:model"]
        let httpSources = context.fingerprintCorpus.isEmpty ? [] : ["fingerprint:http"]
        let appleContext = context.vendor.contains("apple") ||
        context.fingerprintCorpus.contains("apple") ||
        context.fingerprintModel.contains("apple") ||
        context.fingerprintModel.hasPrefix("mac") ||
        context.fingerprintModel.hasPrefix("appletv")

        if appleContext && ClassificationRuleHelpers.classifyAppleModel(fingerprintModelRaw: context.fingerprintModelRaw,
                                                                        fingerprintModel: context.fingerprintModel,
                                                                        modelSources: modelSources,
                                                                        httpSources: httpSources,
                                                                        accumulator: &accumulator) {
            return
        }

        if appleContext && (context.fingerprintModel.contains("appletv") || context.fingerprintCorpus.contains("appletv")) {
            accumulator.add(formFactor: .tv,
                             rawType: nil,
                             confidence: .high,
                             reason: "Fingerprint indicates Apple TV",
                             sources: !modelSources.isEmpty ? modelSources : httpSources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && (context.fingerprintModel.contains("homepod") || context.fingerprintModel.contains("audioaccessory") || context.fingerprintCorpus.contains("homepod") || context.fingerprintCorpus.contains("audioaccessory")) {
            accumulator.add(formFactor: .speaker,
                             rawType: "homepod",
                             confidence: .high,
                             reason: "Fingerprint indicates HomePod",
                             sources: !modelSources.isEmpty ? modelSources : httpSources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && context.fingerprintModel.hasPrefix("macbook") {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            accumulator.add(formFactor: .laptop,
                             rawType: nil,
                             confidence: .high,
                             reason: "Fingerprint indicates MacBook",
                             sources: sources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && (context.fingerprintModel.hasPrefix("macmini") || context.fingerprintModel.contains("mac mini")) {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            accumulator.add(formFactor: .computer,
                             rawType: nil,
                             confidence: .high,
                             reason: "Fingerprint indicates Mac mini class",
                             sources: sources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && context.fingerprintModel.hasPrefix("imac") {
            accumulator.add(formFactor: .computer,
                             rawType: nil,
                             confidence: .high,
                             reason: "Fingerprint indicates iMac",
                             sources: !modelSources.isEmpty ? modelSources : httpSources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && context.fingerprintModel.hasPrefix("macpro") {
            accumulator.add(formFactor: .computer,
                             rawType: nil,
                             confidence: .high,
                             reason: "Fingerprint indicates Mac Pro",
                             sources: !modelSources.isEmpty ? modelSources : httpSources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && context.fingerprintModel.hasPrefix("macstudio") {
            accumulator.add(formFactor: .computer,
                             rawType: nil,
                             confidence: .high,
                             reason: "Fingerprint indicates Mac Studio",
                             sources: !modelSources.isEmpty ? modelSources : httpSources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && (context.fingerprintModel.hasPrefix("iphone") || context.fingerprintModel.hasPrefix("ipod")) {
            accumulator.add(formFactor: .phone,
                             rawType: nil,
                             confidence: .high,
                             reason: "Fingerprint indicates iPhone/iPod",
                             sources: !modelSources.isEmpty ? modelSources : httpSources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && context.fingerprintModel.hasPrefix("ipad") {
            accumulator.add(formFactor: .tablet,
                             rawType: nil,
                             confidence: .high,
                             reason: "Fingerprint indicates iPad",
                             sources: !modelSources.isEmpty ? modelSources : httpSources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && (context.fingerprintModel.hasPrefix("watch") || context.fingerprintModel.contains("watch")) {
            accumulator.add(formFactor: .accessory,
                             rawType: nil,
                             confidence: .medium,
                             reason: "Fingerprint indicates Apple Watch",
                             sources: !modelSources.isEmpty ? modelSources : httpSources,
                             shortCircuitAnnotation: " (authoritative)")
            return
        }
        if appleContext && context.fingerprintModel.hasPrefix("mac") &&
            !context.fingerprintModel.hasPrefix("macbook") &&
            !context.fingerprintModel.hasPrefix("macmini") &&
            !context.fingerprintModel.hasPrefix("macpro") &&
            !context.fingerprintModel.hasPrefix("macstudio") {
            accumulator.add(formFactor: .computer,
                             rawType: nil,
                             confidence: .medium,
                             reason: "Generic Mac fingerprint",
                             sources: !modelSources.isEmpty ? modelSources : httpSources)
        }

        let httpText = context.fingerprintCorpus
        let httpValues = context.fingerprintValues
        if ClassificationRuleHelpers.containsAny(httpText, ["routeros"]) || httpValues.contains(where: { $0.contains("routeros") }) {
            accumulator.add(formFactor: .router,
                             rawType: "routeros",
                             confidence: .high,
                             reason: "HTTP fingerprint indicates RouterOS",
                             sources: httpSources)
        } else if (context.fingerprints?["txt"]?.contains("Echo") ?? false) || (context.fingerprints?["txt"]?.contains("Amazon") ?? false) || (context.fingerprints?["txt"]?.contains("Alexa") ?? false) || (context.fingerprints?["http"]?.contains("Echo") ?? false) || (context.fingerprints?["http"]?.contains("Alexa") ?? false) {
            accumulator.add(formFactor: .iot,
                             rawType: "alexa_echo",
                             confidence: .high,
                             reason: "Fingerprints indicate Amazon Echo/Alexa device",
                             sources: ["fingerprints:echo"])
        } else if context.serviceTypes.contains(where: { $0.rawValue == "_miio._udp" }) || (context.fingerprints?["txt"]?.contains("miio") ?? false) || (context.fingerprints?["txt"]?.contains("0xE0") ?? false) {
            accumulator.add(formFactor: .iot,
                             rawType: "xiaomi",
                             confidence: .high,
                             reason: "Miio service or TXT indicates Xiaomi IoT",
                             sources: ["service:miio", "fingerprints:xiaomi"])
        } else if ClassificationRuleHelpers.containsAny(httpText, ["tp-link", "tplink", "archer"]) || httpValues.contains(where: { $0.contains("tp-link") || $0.contains("tplink") || $0.contains("archer") }) {
            accumulator.add(formFactor: .router,
                             rawType: "tplink_router",
                             confidence: .high,
                             reason: "HTTP fingerprint indicates TP-Link router",
                             sources: httpSources)
        }
        if ClassificationRuleHelpers.containsAny(httpText, ["asus"]) || httpValues.contains(where: { $0.contains("asus") }) {
            accumulator.add(formFactor: .router,
                             rawType: "asus_router",
                             confidence: .high,
                             reason: "HTTP fingerprint indicates ASUS router",
                             sources: httpSources)
        }
        if ClassificationRuleHelpers.containsAny(httpText, ["d-link", "dlink"]) || httpValues.contains(where: { $0.contains("d-link") || $0.contains("dlink") }) {
            accumulator.add(formFactor: .router,
                             rawType: "dlink_router",
                             confidence: .high,
                             reason: "HTTP fingerprint indicates D-Link router",
                             sources: httpSources)
        }
        if ClassificationRuleHelpers.containsAny(httpText, ["netgear"]) || httpValues.contains(where: { $0.contains("netgear") }) {
            accumulator.add(formFactor: .router,
                             rawType: "netgear_router",
                             confidence: .high,
                             reason: "HTTP fingerprint indicates Netgear router",
                             sources: httpSources)
        }
        if ClassificationRuleHelpers.containsAny(httpText, ["miwifi"]) || httpValues.contains(where: { $0.contains("miwifi") }) {
            accumulator.add(formFactor: .router,
                             rawType: "xiaomi_router",
                             confidence: .high,
                             reason: "HTTP fingerprint indicates Xiaomi MIWIFI router",
                             sources: httpSources)
        }
        if ClassificationRuleHelpers.containsAny(httpText, ["synology"]) || httpValues.contains(where: { $0.contains("synology") }) {
            accumulator.add(formFactor: .server,
                             rawType: "synology_nas",
                             confidence: .high,
                             reason: "HTTP fingerprint indicates Synology",
                             sources: httpSources)
        }
        if ClassificationRuleHelpers.containsAny(httpText, ["airport", "time capsule"]) {
            accumulator.add(formFactor: .router,
                             rawType: "airport",
                             confidence: .medium,
                             reason: "HTTP fingerprint indicates AirPort base station",
                             sources: httpSources)
        }
        if let httpTitle = context.fingerprints?["http.title"],
           let match = ClassificationRuleHelpers.classifyHTTPTitle(title: httpTitle) {
            accumulator.add(formFactor: match.formFactor,
                             rawType: match.rawType,
                             confidence: match.confidence,
                             reason: match.reason,
                             sources: ["http.title"],
                             shortCircuitAnnotation: match.authoritative ? " (authoritative)" : nil)
            if match.authoritative { return }
        }
    }
}

struct HostnamePatternClassificationRule: ClassificationRule {
    func evaluate(context: ClassificationRuleContext, accumulator: inout ClassificationAccumulator) async {
        guard !context.host.isEmpty else { return }
        guard !context.services.isEmpty else { return }
        let patterns = [
            Pattern(token: "iphone", formFactor: .phone, rawType: "iphone", confidence: .high, requiresAppleVendor: true),
            Pattern(token: "ipad", formFactor: .tablet, rawType: "ipad", confidence: .high, requiresAppleVendor: true),
            Pattern(token: "macbook", formFactor: .laptop, rawType: "mac", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "mac-mini", formFactor: .computer, rawType: "mac_mini", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "macmini", formFactor: .computer, rawType: "mac_mini", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "imac", formFactor: .computer, rawType: "imac", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "airport", formFactor: .router, rawType: "airport_base_station", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "apple-tv", formFactor: .tv, rawType: "apple_tv", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "appletv", formFactor: .tv, rawType: "apple_tv", confidence: .medium, requiresAppleVendor: true),
            Pattern(token: "homepod", formFactor: .speaker, rawType: "homepod", confidence: .medium, requiresAppleVendor: true)
        ]

        let hasAppleVendor = context.vendor.contains("apple") || context.vendor.contains("ios") || context.vendor.contains("mac")
        let appleServiceTypes: Set<NetworkService.ServiceType> = [.airplay, .airplayAudio, .homekit]
        let appleRawTokens = ["_asquic.", "_companion-link.", "_device-info.", "_touch-able.", "_mediaremotetv.", "_sleep-proxy.", "_remotepairing.", "_apple-mobdev2."]
        let hasAppleService = context.services.contains { svc in
            if appleServiceTypes.contains(svc.type) { return true }
            guard let raw = svc.rawType?.lowercased() else { return false }
            return appleRawTokens.contains { raw.contains($0) }
        }

        for pattern in patterns where context.host.contains(pattern.token) {
            if pattern.requiresAppleVendor {
                if !hasAppleVendor && !hasAppleService { continue }
            }
            accumulator.add(formFactor: pattern.formFactor,
                            rawType: pattern.rawType,
                            confidence: pattern.confidence,
                            reason: "Hostname contains '\(pattern.token)'",
                            sources: ["host:" + pattern.token])
            break
        }
    }

    private struct Pattern {
        let token: String
        let formFactor: DeviceFormFactor?
        let rawType: String?
        let confidence: ClassificationConfidence
        let requiresAppleVendor: Bool
    }
}

struct VendorHostnameClassificationRule: ClassificationRule {
    func evaluate(context: ClassificationRuleContext, accumulator: inout ClassificationAccumulator) async {
        let vendor = context.vendor
        let host = context.host
        let services = context.serviceTypes

        if services.contains(.printer) || services.contains(.ipp) || host.contains("printer") {
            if ClassificationRuleHelpers.containsAny(vendor, ["hp", "canon", "epson", "brother"]) {
                accumulator.add(formFactor: .printer,
                                rawType: "network_printer",
                                confidence: .high,
                                reason: "Printer service + known vendor",
                                sources: ["service:printer", "vendor:printer"])
            } else {
                accumulator.add(formFactor: .printer,
                                rawType: "network_printer",
                                confidence: .medium,
                                reason: "Printer service or hostname",
                                sources: ["service:printer"])
            }
        }
        if host.contains("router") || host.contains("gateway") || host.contains("fw") {
            if ClassificationRuleHelpers.containsAny(vendor, ["ubiquiti", "netgear", "tplink", "tp-link", "asus", "synology", "mikrotik", "linksys"]) {
                accumulator.add(formFactor: .router,
                                rawType: "router",
                                confidence: .high,
                                reason: "Hostname router/gateway + network vendor",
                                sources: ["host:router", "vendor:network"])
            } else {
                accumulator.add(formFactor: .router,
                                rawType: "router",
                                confidence: .medium,
                                reason: "Hostname router/gateway",
                                sources: ["host:router"])
            }
        }
        if context.vendor.contains("apple") && (host.contains("apple-tv") || host.contains("appletv")) {
            accumulator.add(formFactor: .tv,
                            rawType: nil,
                            confidence: .high,
                            reason: "Hostname indicates Apple TV",
                            sources: ["host:appletv"])
        }
        if host.contains("raspberrypi") || host == "pi" || host.hasPrefix("pi-") {
            accumulator.add(formFactor: .computer,
                            rawType: "raspberry_pi",
                            confidence: .medium,
                            reason: "Hostname indicates Raspberry Pi",
                            sources: ["host:raspberrypi"])
        }
        if services.contains(.chromecast) {
            accumulator.add(formFactor: .tv,
                            rawType: "chromecast",
                            confidence: .medium,
                            reason: "Chromecast service",
                            sources: ["mdns:chromecast"])
        }
        if ClassificationRuleHelpers.containsAny(vendor, ["xiaomi", "tplink", "tp-link"]) && (host.contains("plug") || host.contains("smart")) {
            accumulator.add(formFactor: .iot,
                            rawType: "smart_plug",
                            confidence: .medium,
                            reason: "Smart plug hostname + vendor",
                            sources: ["host:plug", "vendor:smart"])
        }
        if host.hasPrefix("zhimi-airpurifier-") {
            accumulator.add(formFactor: .iot,
                            rawType: "xiaomi_air_purifier",
                            confidence: .high,
                            reason: "Hostname indicates Xiaomi Air Purifier",
                            sources: ["host:zhimi-airpurifier"])
        } else if host.hasPrefix("xiaomi-repeater-") {
            accumulator.add(formFactor: .router,
                            rawType: "xiaomi_repeater",
                            confidence: .high,
                            reason: "Hostname indicates Xiaomi Repeater",
                            sources: ["host:xiaomi-repeater"])
        }
    }
}

struct ServiceCombinationClassificationRule: ClassificationRule {
    func evaluate(context: ClassificationRuleContext, accumulator: inout ClassificationAccumulator) async {
        let vendor = context.vendor
        let services = context.serviceTypes

        if vendor.contains("apple") && services.contains(.ssh) && services.contains(.airplay) {
            accumulator.add(formFactor: .computer,
                            rawType: "mac",
                            confidence: .medium,
                            reason: "SSH + AirPlay + Apple vendor",
                            sources: ["service:ssh", "service:airplay", "vendor:apple"])
        }
        if vendor.contains("ubiquiti") && services.contains(.ssh) && services.contains(.http) {
            accumulator.add(formFactor: .router,
                            rawType: "ubiquiti_device",
                            confidence: .medium,
                            reason: "SSH + HTTP mgmt + ubiquiti",
                            sources: ["service:ssh", "service:http", "vendor:ubiquiti"])
        }
        if services.contains(.homekit) && services.count == 1 {
            accumulator.add(formFactor: .accessory,
                            rawType: "homekit_accessory",
                            confidence: .medium,
                            reason: "Single HomeKit service",
                            sources: ["service:homekit"])
        }
        if vendor.contains("apple") && services.contains(.airplayAudio) && !services.contains(.airplay) && !services.contains(.ssh) {
            accumulator.add(formFactor: .speaker,
                            rawType: "homepod",
                            confidence: .medium,
                            reason: "AirPlay Audio only + Apple vendor",
                            sources: ["service:airplayAudio", "vendor:apple"])
        } else if (services.contains(.airplay) || services.contains(.airplayAudio)) && !services.contains(.ssh) && !services.contains(.printer) {
            let src = services.contains(.airplayAudio) && !services.contains(.airplay) ? ["service:airplayAudio"] : ["service:airplay"]
            accumulator.add(formFactor: .tv,
                            rawType: "airplay_target",
                            confidence: .medium,
                            reason: "AirPlay without SSH",
                            sources: src)
        }
    }
}

struct PortProfileClassificationRule: ClassificationRule {
    func evaluate(context: ClassificationRuleContext, accumulator: inout ClassificationAccumulator) async {
        let vendor = context.vendor
        let services = context.serviceTypes
        let ports = context.ports
        let device = context.device

        if services.isEmpty && ports == [80] && ClassificationRuleHelpers.containsAny(vendor, ["tp-link", "tplink", "xiaomi"]) {
            accumulator.add(formFactor: .iot,
                            rawType: "embedded_http",
                            confidence: .medium,
                            reason: "Only port 80 + consumer vendor",
                            sources: ["port:80", "vendor:consumer"])
        }
        if services.isEmpty && device.openPorts.count == 1 && ports.contains(80) && vendor.isEmpty {
            accumulator.add(formFactor: .iot,
                            rawType: "embedded_http",
                            confidence: .low,
                            reason: "Single HTTP port only",
                            sources: ["port:80"])
        }
        if (services.contains(.smb) || ports.contains(445) || ports.contains(139)) &&
            (services.contains(.http) || services.contains(.https) || ports.contains(80) || ports.contains(443)) {
            accumulator.add(formFactor: .server,
                            rawType: "nas",
                            confidence: .medium,
                            reason: "File sharing + web mgmt",
                            sources: ["service:smb_or_ports", "port:web"])
        }
    }
}

struct FallbackClassificationRule: ClassificationRule {
    func evaluate(context: ClassificationRuleContext, accumulator: inout ClassificationAccumulator) async {
        if context.serviceTypes == [.ssh] ||
            (context.services.count == 1 && context.services.first?.type == .ssh) {
            accumulator.add(formFactor: .server,
                            rawType: "ssh_only",
                            confidence: .low,
                            reason: "Only SSH service discovered",
                            sources: ["service:ssh"])
        }
    }
}

// MARK: - Helpers

enum ClassificationRuleHelpers {
    static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    struct HTTPTitleMatch {
        let formFactor: DeviceFormFactor?
        let rawType: String?
        let confidence: ClassificationConfidence
        let reason: String
        let authoritative: Bool
    }

    static func classifyHTTPTitle(title: String) -> HTTPTitleMatch? {
        let lower = title.lowercased()
        if lower.contains("synology") {
            return HTTPTitleMatch(formFactor: .server,
                                  rawType: "synology_nas",
                                  confidence: .high,
                                  reason: "HTTP title indicates Synology appliance",
                                  authoritative: true)
        }
        if lower.contains("routeros") || lower.contains("mikrotik") {
            return HTTPTitleMatch(formFactor: .router,
                                  rawType: "mikrotik_router",
                                  confidence: .high,
                                  reason: "HTTP title indicates MikroTik RouterOS",
                                  authoritative: true)
        }
        if lower.contains("unifi") || lower.contains("ubiquiti") {
            return HTTPTitleMatch(formFactor: .router,
                                  rawType: "ubiquiti_unifi",
                                  confidence: .high,
                                  reason: "HTTP title indicates Ubiquiti UniFi controller",
                                  authoritative: true)
        }
        if lower.contains("pfsense") {
            return HTTPTitleMatch(formFactor: .router,
                                  rawType: "pfsense",
                                  confidence: .high,
                                  reason: "HTTP title indicates pfSense firewall",
                                  authoritative: true)
        }
        if lower.contains("hikvision") {
            return HTTPTitleMatch(formFactor: .camera,
                                  rawType: "hikvision_camera",
                                  confidence: .medium,
                                  reason: "HTTP title indicates Hikvision device",
                                  authoritative: false)
        }
        if lower.contains("laserjet") || lower.contains("hp printer") {
            return HTTPTitleMatch(formFactor: .printer,
                                  rawType: "hp_printer",
                                  confidence: .medium,
                                  reason: "HTTP title indicates HP printer",
                                  authoritative: false)
        }
        if lower.contains("qnap") {
            return HTTPTitleMatch(formFactor: .server,
                                  rawType: "qnap_nas",
                                  confidence: .medium,
                                  reason: "HTTP title indicates QNAP NAS",
                                  authoritative: false)
        }
        return nil
    }

    static func classifyAppleModel(fingerprintModelRaw: String,
                                   fingerprintModel: String,
                                   modelSources: [String],
                                   httpSources: [String],
                                   accumulator: inout ClassificationAccumulator) -> Bool {
        guard !fingerprintModelRaw.isEmpty else { return false }
        let trimmed = fingerprintModelRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let candidates = [trimmed, trimmed.lowercased(), trimmed.uppercased(), fingerprintModel]
        guard let mappedName = candidates.compactMap({ AppleModelDatabase.shared.name(for: $0) }).first else { return false }
        guard let formFactor = appleFormFactor(for: mappedName) else { return false }
        let normalizedRawType = mappedName.lowercased().replacingOccurrences(of: " ", with: "_")
        var sources = !modelSources.isEmpty ? modelSources : httpSources
        if !sources.contains(where: { $0 == "apple:database" }) { sources.append("apple:database") }
        accumulator.add(formFactor: formFactor,
                        rawType: normalizedRawType,
                        confidence: .high,
                        reason: "Fingerprint model maps to Apple database (\(mappedName))",
                        sources: sources,
                        shortCircuitAnnotation: " (authoritative)")
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
}
