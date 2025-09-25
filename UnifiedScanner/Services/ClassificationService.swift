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

private actor ClassificationRulePipelineRegistry {
    private var builder: @Sendable () -> ClassificationRulePipeline = { .default }

    func setBuilder(_ builder: @Sendable @escaping () -> ClassificationRulePipeline) {
        self.builder = builder
    }

    func pipeline() -> ClassificationRulePipeline {
        builder()
    }
}

private let ouiLookupManager = OUILookupManager()
private let rulePipelineRegistry = ClassificationRulePipelineRegistry()

extension ClassificationService {
    static func setOUILookupProvider(_ provider: OUILookupProviding?) {
        Task { await ouiLookupManager.setLookup(provider) }
    }

    static func setRulePipeline(_ builder: @escaping @Sendable () -> ClassificationRulePipeline) {
        Task { await rulePipelineRegistry.setBuilder(builder) }
    }

    static func resetRulePipeline() {
        Task { await rulePipelineRegistry.setBuilder { .default } }
    }
}

// MARK: - Classification Service

// ClassificationService: expanded, modular rule groups with optional OUI (vendor prefix) hook.
struct ClassificationService {
    struct MatchResult: Sendable {
        let formFactor: DeviceFormFactor?
        let rawType: String?
        let confidence: ClassificationConfidence
        let reason: String
        let sources: [String]
    }

    static func classify(device: Device) async -> Device.Classification {
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
        let context = ClassificationRuleContext(device: device,
                                                vendor: vendor,
                                                host: lowerHost,
                                                services: services,
                                                serviceTypes: serviceTypes,
                                                ports: ports,
                                                fingerprintModel: fingerprintModel,
                                                fingerprintModelRaw: fingerprintModelRaw,
                                                fingerprintCorpus: fingerprintCorpus,
                                                fingerprintValues: fingerprintValues,
                                                fingerprints: device.fingerprints)
        var accumulator = ClassificationAccumulator()
        let pipeline = await rulePipelineRegistry.pipeline()

        for rule in pipeline.rules {
            await rule.evaluate(context: context, accumulator: &accumulator)
            if let shortCircuit = accumulator.shortCircuit {
                LoggingService.debug("Authoritative fingerprint classification short-circuited: \(shortCircuit.result.reason)", category: .classification)
                return Device.Classification(formFactor: shortCircuit.result.formFactor,
                                             rawType: shortCircuit.result.rawType,
                                             confidence: shortCircuit.result.confidence,
                                             reason: shortCircuit.result.reason + shortCircuit.annotation,
                                             sources: shortCircuit.result.sources)
            }
        }

        // Consolidate: pick highest confidence, then prefer more sources.
        if let best = accumulator.matches.sorted(by: { (a, b) -> Bool in
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
