import XCTest
@testable import UnifiedScanner

final class DeviceClassificationTests: XCTestCase {
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
}
