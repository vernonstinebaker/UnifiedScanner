import XCTest
@testable import UnifiedScanner

final class DeviceClassificationAdvancedTests: XCTestCase {
    func testRaspberryPiHostname() {
        var d = Device(primaryIP: "192.168.1.101", hostname: "raspberrypi.local", services: [ServiceDeriver.makeService(fromRaw: "_ssh._tcp", port: 22)], openPorts: [])
        d.classification = ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.rawType, "raspberry_pi")
        XCTAssertEqual(d.classification?.formFactor, .computer)
    }

    func testChromecastService() {
        var d = Device(primaryIP: "192.168.1.102", hostname: "chromecast.local", services: [ServiceDeriver.makeService(fromRaw: "_chromecast._tcp", port: 8009)], openPorts: [])
        d.classification = ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.rawType, "chromecast")
        XCTAssertEqual(d.classification?.formFactor, .tv)
    }

    func testHomePodAudioOnly() {
        var d = Device(primaryIP: "192.168.1.103", hostname: "homepod.local", vendor: "Apple", services: [ServiceDeriver.makeService(fromRaw: "_raop._tcp", port: 3689)], openPorts: [])
        // _raop should map to airplayAudio via ServiceDeriver wellKnownPorts
        d.services.append(ServiceDeriver.makeService(fromRaw: "_airplay._tcp", port: 7000)) // ensure not misclassified if both present
        // Actually for HomePod vs Apple TV distinction we want audio only; remove generic airplay
        d.services = d.services.filter { $0.type != .airplay }
        d.classification = ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .speaker)
        XCTAssertEqual(d.classification?.rawType, "homepod")
    }

    func testSmartPlugTPLink() {
        var d = Device(primaryIP: "192.168.1.104", hostname: "plug-2.local", vendor: "TP-Link", services: [], openPorts: [Port(number: 80, serviceName: "http", description: "Embedded", status: .open, lastSeenOpen: Date())])
        d.classification = ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .iot)
    }

    func testNASHeuristic() {
        var d = Device(primaryIP: "192.168.1.105", hostname: "nas-box.local", vendor: "Synology", services: [ServiceDeriver.makeService(fromRaw: "_ssh._tcp", port: 22), ServiceDeriver.makeService(fromRaw: "_http._tcp", port: 5000), ServiceDeriver.makeService(fromRaw: "_smb._tcp", port: 445)], openPorts: [Port(number: 445, serviceName: "smb", description: "SMB", status: .open, lastSeenOpen: Date()), Port(number: 5000, serviceName: "http", description: "Mgmt", status: .open, lastSeenOpen: Date())])
        d.classification = ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.rawType, "nas")
        XCTAssertEqual(d.classification?.formFactor, .server)
    }

    func testHomeKitSingleServiceAccessory() {
        var d = Device(primaryIP: "192.168.1.106", hostname: "hk-light.local", services: [ServiceDeriver.makeService(fromRaw: "_hap._tcp", port: 51827)], openPorts: [])
        d.classification = ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .accessory)
        XCTAssertEqual(d.classification?.rawType, "homekit_accessory")
    }
}
