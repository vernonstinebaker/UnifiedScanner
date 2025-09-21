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
        let fingerprintResult = device.fingerprints.flatMap { VendorModelExtractorService.extract(from: $0) }
        let fingerprintVendor = fingerprintResult?.vendor?.lowercased() ?? ""
        let fingerprintModel = fingerprintResult?.model?.lowercased() ?? ""
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

        // MARK: - High Confidence Vendor / Hostname Patterns
        vendorHostnameRules(vendor: vendor, host: lowerHost, services: serviceTypes, ports: ports, add: add)

        // MARK: - Fingerprint / Model Hint Rules
        fingerprintRules(vendor: vendor,
                         fingerprintModel: fingerprintModel,
                         fingerprintCorpus: fingerprintCorpus,
                         fingerprintValues: fingerprintValues,
                         add: add)

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
    private static func vendorHostnameRules(vendor: String, host: String, services: Set<NetworkService.ServiceType>, ports: Set<Int>, add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        // Apple TV explicit
        if services.contains(.airplay) && vendor.contains("apple") && host.contains("apple-tv") {
            add(.tv, "apple_tv", .high, "AirPlay + Apple vendor + hostname apple-tv", ["mdns:airplay", "vendor:apple", "host:apple-tv"]) }
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
        // Raspberry Pi hostname patterns
        if host.contains("raspberrypi") || host == "pi" || host.hasPrefix("pi-") {
            add(.computer, "raspberry_pi", .medium, "Hostname indicates Raspberry Pi", ["host:raspberrypi"]) }
        // Chromecast
        if services.contains(.chromecast) {
            add(.tv, "chromecast", .medium, "Chromecast service", ["mdns:chromecast"]) }
        // HomePod vs Apple TV (AirPlay audio only)
        if services.contains(.airplayAudio) && !services.contains(.airplay) && vendor.contains("apple") {
            add(.speaker, "homepod", .medium, "AirPlay audio only + Apple vendor", ["mdns:airplayAudio", "vendor:apple"]) }
        // Mac laptop hint
        if vendor.contains("apple") && host.contains("macbook") {
            add(.laptop, "mac_laptop", .medium, "Hostname macbook + Apple vendor", ["host:macbook", "vendor:apple"]) }
        // Xiaomi / TP-Link smart plug style hostnames (iot)
        if containsAny(vendor, ["xiaomi", "tplink", "tp-link"]) && (host.contains("plug") || host.contains("smart")) {
            add(.iot, "smart_plug", .medium, "Smart plug hostname + vendor", ["host:plug", "vendor:smart"]) }
    }

    private static func serviceCombinationRules(vendor: String, host: String, services: Set<NetworkService.ServiceType>, add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        // Apple computer (ssh + airplay)
        if vendor.contains("apple") && services.contains(.ssh) && services.contains(.airplay) {
            add(.computer, "mac", .medium, "SSH + AirPlay + Apple vendor", ["service:ssh", "service:airplay", "vendor:apple"]) }
        // Ubiquiti management (ssh + http)
        if vendor.contains("ubiquiti") && services.contains(.ssh) && services.contains(.http) {
            add(.router, "ubiquiti_device", .medium, "SSH + HTTP mgmt + ubiquiti", ["service:ssh", "service:http", "vendor:ubiquiti"]) }
        // HomeKit accessory (homekit only)
        if services.contains(.homekit) && services.count == 1 {
            add(.accessory, "homekit_accessory", .medium, "Single HomeKit service", ["service:homekit"]) }
        // Media device: AirPlay or Chromecast without SSH suggests non-computer
        if services.contains(.airplay) && !services.contains(.ssh) && !services.contains(.printer) {
            add(.tv, "airplay_target", .medium, "AirPlay without SSH", ["service:airplay"]) }
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
                                         fingerprintCorpus: String,
                                         fingerprintValues: [String],
                                         add: (_ form: DeviceFormFactor?, _ raw: String?, _ conf: ClassificationConfidence, _ reason: String, _ sources: [String]) -> Void) {
        let hasFingerprintData = !fingerprintModel.isEmpty || !fingerprintCorpus.isEmpty
        guard hasFingerprintData else { return }
        let modelSources = fingerprintModel.isEmpty ? [] : ["fingerprint:model"]
        let httpSources = fingerprintCorpus.isEmpty ? [] : ["fingerprint:http"]
        let appleContext = vendor.contains("apple") || fingerprintCorpus.contains("apple") || fingerprintModel.contains("apple") || fingerprintModel.hasPrefix("mac") || fingerprintModel.hasPrefix("appletv")

        if appleContext && (fingerprintModel.contains("appletv") || fingerprintCorpus.contains("appletv")) {
            add(.tv, "apple_tv", .high, "Fingerprint model indicates Apple TV", !modelSources.isEmpty ? modelSources : httpSources)
        }

        if appleContext && (fingerprintModel.contains("homepod") || fingerprintModel.contains("audioaccessory") || fingerprintCorpus.contains("homepod")) {
            add(.speaker, "homepod", .high, "Fingerprint model indicates HomePod", !modelSources.isEmpty ? modelSources : httpSources)
        }

        if appleContext && fingerprintModel.hasPrefix("macbook") {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.laptop, "macbook", .high, "Model identifier indicates MacBook", sources)
        }
        if appleContext && (fingerprintModel.hasPrefix("macmini") || fingerprintModel.contains("mac mini")) {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.computer, "mac_mini", .high, "Model identifier indicates Mac mini", sources)
        }
        if appleContext && fingerprintModel.hasPrefix("imac") {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.computer, "imac", .high, "Model identifier indicates iMac", sources)
        }
        if appleContext && fingerprintModel.hasPrefix("macpro") {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.computer, "mac_pro", .high, "Model identifier indicates Mac Pro", sources)
        }
        if appleContext && fingerprintModel.hasPrefix("macstudio") {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.computer, "mac_studio", .high, "Model identifier indicates Mac Studio", sources)
        }
        if appleContext && (fingerprintModel.hasPrefix("iphone") || fingerprintModel.hasPrefix("ipod")) {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.phone, "iphone", .high, "Model identifier indicates iPhone/iPod", sources)
        }
        if appleContext && fingerprintModel.hasPrefix("ipad") {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.tablet, "ipad", .high, "Model identifier indicates iPad", sources)
        }
        if appleContext && (fingerprintModel.hasPrefix("watch") || fingerprintModel.contains("watch")) {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.accessory, "apple_watch", .medium, "Model identifier indicates Apple Watch", sources)
        }
        if appleContext && fingerprintModel.hasPrefix("mac") &&
            !fingerprintModel.hasPrefix("macbook") &&
            !fingerprintModel.hasPrefix("macmini") &&
            !fingerprintModel.hasPrefix("macpro") &&
            !fingerprintModel.hasPrefix("macstudio") {
            let sources = !modelSources.isEmpty ? modelSources : httpSources
            add(.computer, "mac_computer", .high, "Model identifier indicates Mac", sources)
        }

        let httpText = fingerprintCorpus
        let httpValues = fingerprintValues
        if containsAny(httpText, ["routeros"]) || httpValues.contains(where: { $0.contains("routeros") }) {
            add(.router, "routeros", .high, "HTTP fingerprint indicates RouterOS", httpSources)
        }
        if containsAny(httpText, ["tp-link", "tplink", "archer"]) || httpValues.contains(where: { $0.contains("tp-link") || $0.contains("tplink") || $0.contains("archer") }) {
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
