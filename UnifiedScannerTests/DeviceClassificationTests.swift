import XCTest
@testable import UnifiedScanner

final class DeviceClassificationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ClassificationService.resetRulePipeline()
        // Mock OUI lookup for Apple devices
        ClassificationService.setOUILookupProvider(MockOUILookup())
    }

    override func tearDown() {
        super.tearDown()
        ClassificationService.setOUILookupProvider(nil)
        ClassificationService.resetRulePipeline()
    }
    func testAppleTVHighConfidence() async {
        var d = Device.mockAppleTV
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .tv)
        XCTAssertEqual(d.classification?.confidence, .high)
    }

    func testPrinterClassification() async {
        var d = Device.mockPrinter
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .printer)
        XCTAssertTrue([.high, .medium].contains(d.classification?.confidence))
    }

    func testRouterClassification() async {
        var d = Device.mockRouter
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .router)
    }

    func testSSHOnlyLowConfidence() async {
        var d = Device(primaryIP: "192.168.1.90", services: [ServiceDeriver.makeService(fromRaw: "_ssh._tcp", port: 22)], openPorts: [])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .server)
        XCTAssertEqual(d.classification?.confidence, .low)
    }

    func testAirPlayVsGeneric() async {
        var mac = Device.mockMac
        mac.classification = await ClassificationService.classify(device: mac)
        XCTAssertEqual(mac.classification?.formFactor, .computer)
        // Remove AirPlay to degrade classification
        mac.services = mac.services.filter { $0.type != .airplay }
        mac.classification = await ClassificationService.classify(device: mac)
        // Might classify as computer (still ssh + vendor) but not tv
        XCTAssertNotEqual(mac.classification?.formFactor, .tv)
    }

    func testFingerprintModelElevatesAppleTVConfidence() async {
        var d = Device(primaryIP: "192.168.1.150",
                       hostname: "living-room.local",
                       vendor: "Apple",
                       discoverySources: [.mdns],
                       services: [ServiceDeriver.makeService(fromRaw: "_airplay._tcp", port: 7000)],
                       openPorts: [],
                       fingerprints: ["md": "AppleTV6,2"])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .tv)
        XCTAssertEqual(d.classification?.confidence, .high)
    }

    func testFingerprintModelRecognisesHomePod() async {
        var d = Device(primaryIP: "192.168.1.151",
                       hostname: "kitchen-speaker",
                       vendor: "Apple",
                       discoverySources: [.mdns],
                       services: [ServiceDeriver.makeService(fromRaw: "_raop._tcp", port: 7000)],
                       openPorts: [],
                       fingerprints: ["md": "HomePod", "model": "AudioAccessory5,1"])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .speaker)
        XCTAssertEqual(d.classification?.confidence, .high)
    }

    func testHomePodHeuristicWithoutFingerprint() async {
        var d = Device(primaryIP: "192.168.1.152",
                       hostname: "homepod-kitchen",
                       macAddress: "AA:BB:CC:DD:EE:FF", // Mock Apple MAC
                       discoverySources: [.mdns],
                       services: [ServiceDeriver.makeService(fromRaw: "_raop._tcp", port: 7000)],
                       openPorts: [])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .speaker)
        XCTAssertEqual(d.classification?.confidence, .medium)
        XCTAssertEqual(d.classification?.reason, "AirPlay Audio only + Apple vendor")
    }

    func testHTTPRealmIdentifiesTplinkRouter() async {
        var d = Device(primaryIP: "192.168.1.20",
                       discoverySources: [.portScan],
                       services: [],
                       openPorts: [Port(number: 80, serviceName: "http", description: "UI", status: .open, lastSeenOpen: Date())],
                       fingerprints: ["http.realm": "TP-LINK Wireless N Router WR841N"])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .router)
        XCTAssertEqual(d.classification?.confidence, .high)
    }

    func testHTTPServerIdentifiesRouterOS() async {
        var d = Device(primaryIP: "192.168.1.21",
                       discoverySources: [.portScan],
                       services: [],
                       openPorts: [Port(number: 80, serviceName: "http", description: "UI", status: .open, lastSeenOpen: Date())],
                       fingerprints: ["http.server": "RouterOS v6.45"])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .router)
        XCTAssertEqual(d.classification?.confidence, .high)
    }

    func testMacBookIdentifierClassifiesLaptop() async {
        var d = Device(primaryIP: "192.168.1.30",
                       discoverySources: [.mdns],
                       services: [],
                       openPorts: [],
                       fingerprints: ["model": "MacBookPro16,1"])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .laptop)
        XCTAssertEqual(d.classification?.confidence, .high)
    }

    func testMIWIFIFingerprintClassifiesRouter() async {
        var d = Device(primaryIP: "192.168.1.40",
                       discoverySources: [.portScan],
                       services: [],
                       openPorts: [Port(number: 443, serviceName: "https", description: "UI", status: .open, lastSeenOpen: Date())],
                       fingerprints: ["https.cert.cn": "MIWIFI SERVER CERT"])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .router)
        XCTAssertEqual(d.classification?.confidence, .high)
    }

    func testHostnameDetectsIPhoneWithoutVendor() async {
        let service = ServiceDeriver.makeService(fromRaw: "_companion-link._tcp.", port: nil)
        var d = Device(primaryIP: "192.168.1.60",
                       hostname: "mom-iphone.local",
                       discoverySources: [.mdns],
                       services: [service])
        d.classification = await ClassificationService.classify(device: d)
        let classification = d.classification
        XCTAssertNotNil(classification)
        XCTAssertEqual(classification?.formFactor, .phone)
        XCTAssertEqual(classification?.confidence, .high)
        XCTAssertEqual(classification?.reason, "Hostname contains 'iphone'")
    }

    func testHostnameApplePatternSkippedForNonAppleVendor() async {
        let nonAppleService = ServiceDeriver.makeService(fromRaw: "_http._tcp.", port: 80)
        var d = Device(primaryIP: "192.168.1.61",
                       hostname: "marketing-ipad",
                       vendor: "Samsung",
                       discoverySources: [.mdns],
                       services: [nonAppleService])
        d.classification = await ClassificationService.classify(device: d)
        let classification = d.classification
        XCTAssertNotNil(classification)
        XCTAssertNotEqual(classification?.formFactor, .tablet)
        XCTAssertFalse(classification?.sources.contains(where: { $0.hasPrefix("host:") }) ?? false)
    }

    func testHostnamePatternRequiresServicePresence() async {
        var d = Device(primaryIP: "192.168.1.62",
                       hostname: "spoof-iphone",
                       discoverySources: [.arp])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertNotEqual(d.classification?.formFactor, .phone)
    }

    func testAppleVendorAllowsHostnamePattern() async {
        let genericService = ServiceDeriver.makeService(fromRaw: "_http._tcp.", port: 80)
        var d = Device(primaryIP: "192.168.1.63",
                       hostname: "family-ipad",
                       vendor: "Apple",
                       discoverySources: [.mdns],
                       services: [genericService])
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .tablet)
    }

    func testAppleModelFingerprintUsesDatabase() async {
        var d = Device(primaryIP: "192.168.1.120",
                       vendor: "Apple",
                       discoverySources: [.mdns],
                       services: [],
                       openPorts: [],
                       fingerprints: ["model": "Mac16,11"])
        d.classification = await ClassificationService.classify(device: d)
        let classification = d.classification
        XCTAssertEqual(classification?.confidence, .high)
        XCTAssertEqual(classification?.formFactor, .computer)
        XCTAssertEqual(classification?.rawType, "mac_mini")
        XCTAssertTrue(classification?.reason.contains("Apple database") ?? false)
        XCTAssertTrue(classification?.sources.contains("fingerprint:model") ?? false)
    }

    func testFingerprintRuleShortCircuitsAuthoritativeMatch() async {
        ClassificationService.setRulePipeline {
            ClassificationRulePipeline(rules: [FingerprintClassificationRule()])
        }
        defer { ClassificationService.resetRulePipeline() }
        var device = Device(primaryIP: "10.0.0.50",
                            vendor: "Apple",
                            discoverySources: [.mdns],
                            services: [],
                            openPorts: [],
                            fingerprints: ["model": "MacBookPro16,1"])
        let classification = await ClassificationService.classify(device: device)
        XCTAssertEqual(classification.formFactor, .laptop)
        XCTAssertEqual(classification.confidence, .high)
        XCTAssertTrue(classification.reason.contains("Apple database"), "reason=\(classification.reason)")
        XCTAssertTrue(classification.reason.contains("authoritative"), "reason=\(classification.reason)")
    }

    func testHostnamePatternRuleMatchesIPhoneWhenAppleSignalsPresent() async {
        ClassificationService.setRulePipeline {
            ClassificationRulePipeline(rules: [HostnamePatternClassificationRule()])
        }
        defer { ClassificationService.resetRulePipeline() }
        let service = ServiceDeriver.makeService(fromRaw: "_companion-link._tcp.", port: nil)
        var device = Device(primaryIP: "10.0.0.60",
                            hostname: "kitchen-iphone",
                            discoverySources: [.mdns],
                            services: [service])
        let classification = await ClassificationService.classify(device: device)
        XCTAssertEqual(classification.formFactor, .phone)
        XCTAssertEqual(classification.confidence, .high)
        XCTAssertTrue(classification.reason.contains("iphone"))
    }

    func testVendorHostnameRuleIdentifiesPrinterVendors() async {
        ClassificationService.setRulePipeline {
            ClassificationRulePipeline(rules: [VendorHostnameClassificationRule()])
        }
        defer { ClassificationService.resetRulePipeline() }
        let printerService = ServiceDeriver.makeService(fromRaw: "_ipp._tcp.", port: 631)
        var device = Device(primaryIP: "10.0.0.61",
                            hostname: "office-printer",
                            vendor: "HP",
                            discoverySources: [.mdns],
                            services: [printerService])
        let classification = await ClassificationService.classify(device: device)
        XCTAssertEqual(classification.formFactor, .printer)
        XCTAssertEqual(classification.confidence, .high)
        XCTAssertTrue(classification.sources.contains("vendor:printer"))
    }

    func testServiceCombinationRuleDetectsAppleComputer() async {
        ClassificationService.setRulePipeline {
            ClassificationRulePipeline(rules: [ServiceCombinationClassificationRule()])
        }
        defer { ClassificationService.resetRulePipeline() }
        let ssh = ServiceDeriver.makeService(fromRaw: "_ssh._tcp.", port: 22)
        let airplay = ServiceDeriver.makeService(fromRaw: "_airplay._tcp.", port: 7000)
        var device = Device(primaryIP: "10.0.0.62",
                            vendor: "Apple",
                            discoverySources: [.mdns],
                            services: [ssh, airplay])
        let classification = await ClassificationService.classify(device: device)
        XCTAssertEqual(classification.formFactor, .computer)
        XCTAssertEqual(classification.rawType, "mac")
        XCTAssertEqual(classification.confidence, .medium)
    }

    func testPortProfileRuleDetectsNASCharacteristics() async {
        ClassificationService.setRulePipeline {
            ClassificationRulePipeline(rules: [PortProfileClassificationRule()])
        }
        defer { ClassificationService.resetRulePipeline() }
        let smb = ServiceDeriver.makeService(fromRaw: "_smb._tcp.", port: 445)
        let http = ServiceDeriver.makeService(fromRaw: "_http._tcp.", port: 80)
        let smbPort = Port(number: 445, serviceName: "smb", description: "SMB", status: .open, lastSeenOpen: Date())
        let httpPort = Port(number: 80, serviceName: "http", description: "HTTP", status: .open, lastSeenOpen: Date())
        var device = Device(primaryIP: "10.0.0.63",
                            discoverySources: [.portScan],
                            services: [smb, http],
                            openPorts: [smbPort, httpPort])
        let classification = await ClassificationService.classify(device: device)
        XCTAssertEqual(classification.formFactor, .server)
        XCTAssertEqual(classification.rawType, "nas")
        XCTAssertEqual(classification.confidence, .medium)
    }
}

// Mock OUI lookup for tests
private final class MockOUILookup: OUILookupProviding {
    func vendorFor(mac: String) -> String? {
        let upper = mac.uppercased().replacingOccurrences(of: "-", with: ":")
        if upper.hasPrefix("AA:BB:CC") { return "Apple" } // Mock Apple OUI
        return nil
    }
}
