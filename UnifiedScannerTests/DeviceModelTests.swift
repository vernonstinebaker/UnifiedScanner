import XCTest
@testable import UnifiedScanner

final class DeviceModelTests: XCTestCase {
    func testIdentityPrefersMAC() {
        let d = Device(primaryIP: "192.168.0.10", hostname: "host", macAddress: "aa:bb:cc:00:11:22")
        XCTAssertEqual(d.id, "AA:BB:CC:00:11:22")
    }

    func testIdentityFallsBackToPrimaryIP() {
        let d = Device(primaryIP: "192.168.0.20", hostname: "host")
        XCTAssertEqual(d.id, "192.168.0.20")
    }

    func testBestDisplayIPPrefersPrivateIPv4() {
        let ips: Set<String> = ["8.8.8.8", "192.168.1.10"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "192.168.1.10")
    }

    func testOnlineDerivationUsesGraceInterval() {
        var d = Device(primaryIP: "192.168.0.3")
        XCTAssertFalse(d.isOnline)
        d.lastSeen = Date().addingTimeInterval(-100)
        XCTAssertTrue(d.isOnline)
    }

    func testServiceDedupIncludesPortDerived() {
        let svc = NetworkService(name: "SSH", type: .ssh, rawType: "_ssh._tcp", port: 22, isStandardPort: true)
        let d = Device(primaryIP: "192.168.0.5", services: [svc], openPorts: [Port(number: 80, serviceName: "http", description: "Web", status: .open, lastSeenOpen: Date())])
        let names = d.displayServices.map { $0.name }
        XCTAssertTrue(names.contains("HTTP"))
        XCTAssertTrue(names.contains("SSH"))
    }

    func testMocksNonEmptyAndUniqueIDs() {
        let mocks = Device.allMocks
        XCTAssertFalse(mocks.isEmpty)
        let ids = Set(mocks.map { $0.id })
        XCTAssertEqual(ids.count, mocks.count)
    }

    func testNormalizeMAC() {
        XCTAssertEqual(Device.normalizeMAC("aa:bb:cc:dd:ee:ff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(Device.normalizeMAC("aabbccddeeff"), "AABBCCDDEEFF")
        XCTAssertEqual(Device.normalizeMAC("AA-BB-CC-DD-EE-FF"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(Device.normalizeMAC("aa-bb-cc-dd-ee-f"), "AA:BB:CC:DD:EE:0F")
    }

    func testIdentityWithExplicitID() {
        let d = Device(id: "explicit", primaryIP: "1.2.3.4")
        XCTAssertEqual(d.id, "explicit")
    }

    func testIdentityFallsBackToHostname() {
        let d = Device(hostname: "myhost.local")
        XCTAssertEqual(d.id, "myhost.local")
    }

    func testIdentityDefaultsToUUID() {
        let d1 = Device()
        let d2 = Device()
        XCTAssertNotEqual(d1.id, d2.id)
        let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        let uuidRegex = try! NSRegularExpression(pattern: uuidPattern, options: [.caseInsensitive])
        let range = NSRange(d1.id.startIndex..<d1.id.endIndex, in: d1.id)
        XCTAssertNotNil(uuidRegex.firstMatch(in: d1.id, options: [], range: range))
    }

    func testOnlineOverride() {
        var d = Device(lastSeen: Date().addingTimeInterval(-1000))
        XCTAssertFalse(d.isOnline)
        d.isOnlineOverride = true
        XCTAssertTrue(d.isOnline)
        d.isOnlineOverride = false
        XCTAssertFalse(d.isOnline)
    }

    func testRecentlySeenEdgeCases() {
        var d = Device(lastSeen: Date().addingTimeInterval(-DeviceConstants.onlineGraceInterval + 1))
        XCTAssertTrue(d.recentlySeen)
        d.lastSeen = Date().addingTimeInterval(-DeviceConstants.onlineGraceInterval)
        XCTAssertFalse(d.recentlySeen)
        d.lastSeen = nil
        XCTAssertFalse(d.recentlySeen)
    }

    func testDisplayServicesDeduplication() {
        let explicitHTTP = NetworkService(name: "Custom HTTP", type: .http, rawType: nil, port: 80, isStandardPort: true)
        let portDerivedSSH = Port(number: 22, serviceName: "ssh", description: "SSH", status: .open, lastSeenOpen: Date())
        let d = Device(services: [explicitHTTP], openPorts: [portDerivedSSH])
        let display = d.displayServices
        XCTAssertEqual(display.count, 2)
        XCTAssertTrue(display.contains { $0.type == .http && $0.name == "Custom HTTP" })
        XCTAssertTrue(display.contains { $0.type == .ssh && $0.name == "SSH" })
    }

    func testBestDisplayIPHandlesIPv6() {
        let ips: Set<String> = ["fe80::1", "2001:db8::1", "192.0.2.1"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "192.0.2.1") // Prefers IPv4
    }

    func testBestDisplayIPEmpty() {
        XCTAssertNil(IPHeuristics.bestDisplayIP([]))
    }

    func testBestDisplayIPOnlyLinkLocal() {
        let ips: Set<String> = ["169.254.1.1", "fe80::1"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "169.254.1.1") // IPv4 link-local preferred over IPv6 link-local
    }

    func testClassificationInitAndHashable() {
        let classif = Device.Classification(formFactor: .phone, rawType: "iPhone", confidence: .high, reason: "MDNS match", sources: ["mdns"])
        XCTAssertEqual(classif.formFactor, .phone)
        XCTAssertEqual(classif.confidence, .high)
        XCTAssertEqual(classif.sources.count, 1)

        let same = Device.Classification(formFactor: .phone, rawType: "iPhone", confidence: .high, reason: "MDNS match", sources: ["mdns"])
        XCTAssertEqual(classif, same)
    }

    func testNetworkServiceInitAndIdentifiable() {
        let svc = NetworkService(name: "Test", type: .http, rawType: "_http._tcp", port: 8080, isStandardPort: false)
        XCTAssertEqual(svc.name, "Test")
        XCTAssertEqual(svc.type, .http)
        XCTAssertNotNil(svc.id)
    }

    func testPortInitAndStatus() {
        let port = Port(number: 80, serviceName: "http", description: "Web", status: .open, lastSeenOpen: Date())
        XCTAssertEqual(port.number, 80)
        XCTAssertEqual(port.status, .open)
        XCTAssertNotNil(port.id)
    }

    func testDeviceCodableRoundtrip() {
        let original = Device(id: "test", primaryIP: "192.168.1.1", services: [NetworkService(name: "HTTP", type: .http, rawType: nil, port: 80, isStandardPort: true)])
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        if let data = try? encoder.encode(original),
           let decoded = try? decoder.decode(Device.self, from: data) {
            XCTAssertEqual(original.id, decoded.id)
            XCTAssertEqual(original.primaryIP, decoded.primaryIP)
            XCTAssertEqual(original.services.count, decoded.services.count)
        } else {
            XCTFail("Codable roundtrip failed")
        }
    }

    func testDeviceHashable() {
        let d1 = Device(primaryIP: "192.168.1.1")
        let d2 = Device(primaryIP: "192.168.1.1")
        let d3 = Device(primaryIP: "192.168.1.2")
        XCTAssertEqual(d1, d2)
        XCTAssertNotEqual(d1, d3)
        let set: Set<Device> = [d1, d2, d3]
        XCTAssertEqual(set.count, 2)
    }

    func testEnumCases() {
        let formFactors = DeviceFormFactor.allCases
        XCTAssertEqual(formFactors.count, 15)
        XCTAssertTrue(formFactors.contains(.router))
        XCTAssertTrue(formFactors.contains(.unknown))

        let confidences = ClassificationConfidence.allCases
        XCTAssertEqual(confidences.count, 4)
        XCTAssertTrue(confidences.contains(.high))

        let sources = DiscoverySource.allCases
        XCTAssertEqual(sources.count, 9)
        XCTAssertTrue(sources.contains(.mdns))

        let serviceTypes = NetworkService.ServiceType.allCases
        XCTAssertEqual(serviceTypes.count, 17)
        XCTAssertTrue(serviceTypes.contains(.other))

        let portStatuses: [UnifiedScanner.Port.Status] = [.open, .filtered, .closed]
        XCTAssertEqual(portStatuses.count, 3)
        XCTAssertTrue(portStatuses.contains(UnifiedScanner.Port.Status.filtered))
    }
}
